defmodule Mix.Tasks.Ec100.Release do
  use Mix.Task

  @shortdoc "Collect EC100 system, license, and source release assets"
  @moduledoc """
  Run after `mix nerves.artifact.build` on Linux with Docker.

  Writes the system tarball, source tarball, and SHA256SUMS into an empty `dist/`.
  Nerves 2 pre.3 does not run the legacy build_runner_opts legal-info target.
  """

  alias Nerves.Container

  @impl Mix.Task
  def run([]) do
    unless match?({:unix, :linux}, :os.type()) and Container.tool() == "docker" do
      Mix.raise("Release asset collection requires Linux and Docker")
    end

    plan = Nerves.build_plan()
    package = Nerves.BuildPlan.find_package(plan, :nerves_system_ec100)
    [%{archive_path: archive}] = package.downloads

    unless File.regular?(archive) do
      Mix.raise("Run mix nerves.artifact.build before collecting release assets")
    end

    File.mkdir_p!("dist")

    if File.ls!("dist") != [] do
      Mix.raise("dist must be empty before collecting release assets")
    end

    ["run" | args] =
      Container.artifact_run_args(
        plan,
        package,
        "docker",
        Container.package_image!("docker", package),
        Nerves.Paths.download_dir(),
        ["/workspace/nerves_system_ec100/release/assets.sh"]
      )

    # Reuse Nerves' mounts and environment, but run the collector without a TTY.
    args =
      ["run", "--entrypoint", "/bin/bash", "--volume", "#{Path.expand("dist")}:/dist"] ++
        List.delete(args, "-it")

    {_, status} =
      System.cmd("docker", args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("Release asset collection failed (#{status})")
    end

    Mix.shell().info("Release assets and SHA256SUMS are in dist/")
  end
end
