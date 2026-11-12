defmodule NervesSystemEC100.MixProject do
  use Mix.Project

  @app :nerves_system_ec100
  @version Path.join(__DIR__, "VERSION") |> File.read!() |> String.trim()

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      compilers: Mix.compilers() ++ [:nerves_package],
      nerves_package: nerves_package(),
      description: "Minimal Nerves system for the IOTRouter EC100 (Rockchip RK3506J)",
      deps: deps()
    ]
  end

  def application, do: []

  def cli, do: [default_target: :target]

  defp nerves_package do
    [
      type: :system,
      artifact_sites: [{:github_releases, "sid2baker/#{@app}"}],
      artifact_checksum: true,
      build_runner_opts: [make_args: ["source", "all", "legal-info"]],
      platform: Nerves.System.BR,
      platform_config: [defconfig: "nerves_defconfig"],
      env: [
        {"TARGET_ARCH", "arm"},
        {"TARGET_CPU", "cortex_a7"},
        {"TARGET_OS", "linux"},
        {"TARGET_ABI", "gnueabihf"},
        {"TARGET_GCC_FLAGS",
         "-mabi=aapcs-linux -mfpu=neon-vfpv4 -marm -fstack-protector-strong " <>
           "-mfloat-abi=hard -mcpu=cortex-a7 -fPIE -pie -Wl,-z,now -Wl,-z,relro"}
      ],
      checksum: source_fingerprint_files()
    ]
  end

  defp deps do
    [
      {:nerves, "~> 2.0 or ~> 2.0.0-pre.9", runtime: false},
      {:nerves_system_br, "1.34.5", runtime: false},
      {:nerves_toolchain_armv7_nerves_linux_gnueabihf, "~> 15.3.0", runtime: false},
      {:nerves_system_linter, "~> 0.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp source_fingerprint_files do
    [
      "config/config.exs",
      "bootstrap",
      "dts",
      "ec100.its",
      "linux",
      "patches",
      "rootfs_overlay",
      "fwup-ops.conf",
      "fwup.conf",
      "mix.exs",
      "nerves_defconfig",
      "post-build.sh",
      "post-createfs.sh"
    ]
  end
end
