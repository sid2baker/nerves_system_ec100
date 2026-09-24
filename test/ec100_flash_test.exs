defmodule EC100FlashTest do
  use ExUnit.Case, async: true
  alias Mix.Tasks.Ec100.Flash

  test "only factory regions are planned; payload sizes round up to sectors" do
    plan = Flash.regions!(%{"data/ec100.itb" => 513, "data/rootfs.img" => 1024})
    assert {"fit-a", 32768, 2} in plan
    assert {"rootfs-a", 163_840, 2} in plan
    assert {"initialize-data", 1_212_416, 256} in plan

    assert Enum.filter(plan, fn {_, sector, _} -> sector < 32768 end) ==
             [{"mbr", 0, 1}, {"env-a", 24576, 256}, {"env-b", 24832, 256}]
  end

  test "factory boot area places SPL at LBA64 and U-Boot at LBA16384, below env" do
    boot = Flash.boot_area!(<<1, 2, 3>>, <<4, 5, 6>>)
    assert byte_size(boot) == (24576 - 64) * 512
    assert binary_part(boot, 0, 4) == <<1, 2, 3, 0>>
    assert binary_part(boot, (16384 - 64) * 512, 4) == <<4, 5, 6, 0>>
    assert_raise Mix.Error, fn -> Flash.boot_area!(<<1>>, :binary.copy(<<0>>, 4_194_305)) end
    assert_raise Mix.Error, fn -> Flash.boot_area!(<<>>, <<1>>) end
  end

  test "missing and oversized payloads fail closed" do
    assert_raise Mix.Error, fn -> Flash.regions!(%{}) end

    assert_raise Mix.Error, fn ->
      Flash.regions!(%{"data/ec100.itb" => 33_554_433, "data/rootfs.img" => 1024})
    end
  end

  test "real fwup complete task prepares p1/p2/p3 without USB access" do
    tmp = Path.join(System.tmp_dir!(), "ec100-flash-test-#{System.unique_integer([:positive])}")
    images = Path.join(tmp, "images")
    File.mkdir_p!(images)
    on_exit(fn -> File.rm_rf!(tmp) end)
    File.write!(Path.join(images, "ec100.itb"), :binary.copy(<<0xAB>>, 1024))
    File.write!(Path.join(images, "rootfs.squashfs"), :binary.copy(<<0xCD>>, 1024))

    for name <- ["idbloader.img", "u-boot.itb"],
        do: File.write!(Path.join(images, name), <<1, 2, 3>>)

    hash = :crypto.hash(:sha256, <<1, 2, 3>>) |> Base.encode16(case: :lower)

    File.write!(
      Path.join(images, "bootloader.sha256"),
      "#{hash}  idbloader.img\n#{hash}  u-boot.itb\n"
    )

    firmware = Path.join(tmp, "test.fw")
    fwup = System.find_executable("fwup") || flunk("fwup required for factory integration test")

    {output, status} =
      System.cmd(fwup, ["-c", "-f", "fwup.conf", "-o", firmware],
        stderr_to_stdout: true,
        env: [
          {"NERVES_SYSTEM", tmp},
          {"NERVES_SDK_VERSION", "test"},
          {"NERVES_FW_VCS_IDENTIFIER", "test"},
          {"NERVES_FW_MISC", "test"}
        ]
      )

    assert status == 0, output
    destination = Path.join(tmp, "prepared")

    files = Flash.prepare!(firmware, images, 7_471_104, destination)
    assert {"boot-area", 64, 24512, Path.join(destination, "boot-area.bin")} in files

    assert {"clear-backup-gpt", 7_471_071, 33, Path.join(destination, "clear-backup-gpt.bin")} in files

    assert File.read!(Path.join(destination, "fit-a.bin")) == :binary.copy(<<0xAB>>, 1024)
    assert File.read!(Path.join(destination, "rootfs-a.bin")) == :binary.copy(<<0xCD>>, 1024)

    assert File.read!(Path.join(destination, "initialize-data.bin")) ==
             :binary.copy(<<255>>, 131_072)

    assert :ok == Flash.validate_mbr!(File.read!(Path.join(destination, "mbr.bin")), 7_471_104)

    # Exercise both fwup creation and application: escaped ${name} used to be
    # consumed on the second pass, leaving a bare `mmc read` and `bootm`.
    expected_env =
      File.read!("bootstrap/uboot.env")
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))

    for name <- ["env-a.bin", "env-b.bin"] do
      <<_crc_and_flag::binary-size(5), data::binary>> = File.read!(Path.join(destination, name))
      entries = :binary.split(data, <<0>>, [:global])
      for entry <- expected_env, do: assert(entry in entries, "#{name} missing #{entry}")

      # Nerves.Runtime.Init formats the initially blank data partition after
      # Erlang starts. Do not replace it with a second early-boot formatter.
      for entry <- [
            "a.nerves_fw_application_part0_devpath=/dev/rootdisk0p3",
            "a.nerves_fw_application_part0_fstype=ext4",
            "a.nerves_fw_application_part0_target=/root"
          ],
          do: assert(entry in entries, "#{name} missing #{entry}")
    end

    assert_raise Mix.Error, ~r/Output already exists/, fn ->
      Flash.prepare!(firmware, images, 7_471_104, destination)
    end

    File.write!(Path.join(images, "u-boot.itb"), "corrupted")

    assert_raise Mix.Error, ~r/Bootloader checksum mismatch/, fn ->
      Flash.prepare!(firmware, images, 7_471_104, destination <> "-bad")
    end

    refute File.exists?(destination <> "-bad")
  end

  test "detects exactly one correct MASKROM device" do
    device = "DevNo=1 Vid=0x2207,Pid=0x350f,LocationID=105 Maskrom"
    assert Flash.device!(device <> "\n") == device

    for listing <- [
          "not found any devices!",
          device <> "\n" <> device,
          "DevNo=1 Vid=0x2207,Pid=0x1234 Maskrom",
          "DevNo=1 Vid=0x2207,Pid=0x350f Loader"
        ] do
      assert_raise Mix.Error, fn -> Flash.device!(listing) end
    end
  end

  test "install backs up first, verifies writes, and writes MBR last" do
    tmp = Path.join(System.tmp_dir!(), "ec100-install-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    payload = Path.join(tmp, "payload")
    File.write!(payload, :binary.copy(<<7>>, 512))

    run = fn args ->
      send(self(), {:command, args})

      case args do
        ["rl", "0", "10", path] -> File.write!(path, :binary.copy(<<0>>, 5120))
        ["rl", _, "1", path] -> File.cp!(payload, path)
        ["wl", _, _] -> :ok
      end

      "OK"
    end

    files = [{"mbr", 0, 1, payload}, {"fit-a", 3, 1, payload}]
    Flash.install!(run, files, 10, tmp)
    backup = Path.join(tmp, "emmc-before.img")
    assert_receive {:command, ["rl", "0", "10", ^backup]}
    assert_receive {:command, ["wl", "3", ^payload]}
    assert_receive {:command, ["rl", "3", "1", _]}
    assert_receive {:command, ["wl", "0", ^payload]}
    assert_receive {:command, ["rl", "0", "1", _]}
    assert File.exists?(backup <> ".sha256")

    bad_readback = fn
      ["rl", "0", "10", path] -> File.write!(path, :binary.copy(<<0>>, 5120))
      ["rl", _, "1", path] -> File.write!(path, :binary.copy(<<0>>, 512))
      ["wl", sector, _] -> send(self(), {:write, sector})
    end

    assert_raise Mix.Error, ~r/Readback mismatch/, fn ->
      Flash.install!(bad_readback, files, 10, tmp)
    end

    assert_receive {:write, "3"}
    refute_receive {:write, "0"}
    bad_backup = fn ["rl", "0", "10", path] -> File.write!(path, <<0>>) end

    assert_raise Mix.Error, ~r/Incomplete backup/, fn ->
      Flash.install!(bad_backup, files, 10, tmp)
    end
  end

  test "backup can be skipped without skipping readback verification" do
    tmp = Path.join(System.tmp_dir!(), "ec100-no-backup-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    payload = Path.join(tmp, "payload")
    File.write!(payload, :binary.copy(<<7>>, 512))
    files = [{"fit-a", 3, 1, payload}]

    # No full-device read clause: attempting a backup fails this test.
    run = fn
      ["wl", "3", ^payload] ->
        send(self(), :written)

      ["rl", "3", "1", path] ->
        send(self(), :verified)
        File.cp!(payload, path)
    end

    Flash.install!(run, files, 10, tmp, backup: false)
    assert_receive :written
    assert_receive :verified
    refute File.exists?(Path.join(tmp, "emmc-before.img"))
    refute File.exists?(Path.join(tmp, "emmc-before.img.sha256"))

    bad_readback = fn
      ["wl", "3", ^payload] -> :ok
      ["rl", "3", "1", path] -> File.write!(path, :binary.copy(<<0>>, 512))
    end

    assert_raise Mix.Error, ~r/Readback mismatch/, fn ->
      Flash.install!(bad_readback, files, 10, tmp, backup: false)
    end
  end

  test "MBR must exactly match current layout and requested capacity" do
    sectors = 7_471_104

    entries =
      for {start, count} <- [
            {163_840, 524_288},
            {688_128, 524_288},
            {1_212_416, sectors - 1_212_416}
          ] do
        <<0::32, 0x83, 0::24, start::little-32, count::little-32>>
      end

    mbr = IO.iodata_to_binary([:binary.copy(<<0>>, 446), entries, <<0::128, 0x55, 0xAA>>])
    assert :ok == Flash.validate_mbr!(mbr, sectors)
    assert_raise Mix.Error, fn -> Flash.validate_mbr!(mbr, sectors + 1) end
    assert_raise Mix.Error, fn -> Flash.validate_mbr!(<<0::4096>>, sectors) end
  end
end
