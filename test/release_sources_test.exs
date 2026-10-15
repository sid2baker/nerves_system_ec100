defmodule ReleaseSourcesTest do
  use ExUnit.Case, async: true

  @script Path.expand("../release/download-sources.sh", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "ec100-sources-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.cp!(@script, Path.join(dir, "download-sources.sh"))

    source = Path.join(dir, "source.tar.xz")
    File.write!(source, "verified source archive")
    checksum = :crypto.hash(:sha512, File.read!(source)) |> Base.encode16(case: :lower)

    File.write!(
      Path.join(dir, "toolchain-sources.sha512"),
      "# Test sources\n\n#{checksum} file://#{source}\n"
    )

    cache = Path.join(dir, "download cache")
    %{dir: dir, source: source, cache: cache, archive: Path.join(cache, "source.tar.xz")}
  end

  test "downloads verified bytes and reuses the cache without network access", context do
    assert {output, 0} = download(context)
    assert output =~ "Source: source.tar.xz"
    assert File.read!(context.archive) == File.read!(context.source)
    refute File.exists?(context.archive <> ".part")

    File.rm!(context.source)
    assert {_, 0} = download(context)
  end

  test "rejects a changed download before promoting it into the cache", context do
    File.write!(context.source, "changed upstream bytes")
    {output, status} = download(context)
    assert status != 0
    assert output =~ "FAILED"
    refute File.exists?(context.archive)
  end

  test "rechecks cached bytes and fails on corruption", context do
    assert {_, 0} = download(context)
    File.write!(context.archive, "corrupt cache")
    {output, status} = download(context)
    assert status != 0
    assert output =~ "FAILED"
  end

  test "bounds curl retries and never accepts a partial failed transfer", context do
    bin = Path.join(context.dir, "bin")
    File.mkdir_p!(bin)
    curl = Path.join(bin, "curl")
    log = Path.join(context.dir, "curl.args")

    File.write!(curl, """
    #!/bin/sh
    printf '%s\n' "$@" > "$CURL_ARGS"
    printf partial > "$PARTIAL"
    exit 56
    """)

    File.chmod!(curl, 0o755)

    assert {_, 56} =
             download(context, [
               {"PATH", bin <> ":" <> System.fetch_env!("PATH")},
               {"CURL_ARGS", log},
               {"PARTIAL", context.archive <> ".part"}
             ])

    args = File.read!(log) |> String.split("\n", trim: true)
    pairs = Enum.chunk_every(args, 2, 1, :discard)
    assert ["--connect-timeout", "15"] in pairs
    assert ["--max-time", "300"] in pairs
    assert ["--speed-time", "30"] in pairs
    assert ["--retry", "2"] in pairs
    assert "--retry-all-errors" in args
    refute File.exists?(context.archive)

    assert {_, 0} = download(context)
    assert File.read!(context.archive) == File.read!(context.source)
    refute File.exists?(context.archive <> ".part")
  end

  defp download(context, env \\ []) do
    System.cmd("bash", [Path.join(context.dir, "download-sources.sh"), context.cache],
      stderr_to_stdout: true,
      env: env
    )
  end
end
