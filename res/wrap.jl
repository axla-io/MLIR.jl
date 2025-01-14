# generate LLVM wrappers

using Clang.Generators

cd(@__DIR__)
options = load_options(joinpath(@__DIR__, "wrap.toml"))

@add_def off_t
@add_def MlirTypesCallback

import Pkg
import BinaryBuilderBase: PkgSpec, Prefix, temp_prefix, setup_dependencies, cleanup_dependencies, destdir

const dependencies = PkgSpec[PkgSpec(; name = "LLVM_full_jll")]

const libdir = joinpath(@__DIR__, "..", "lib")

function rewrite!(dag::ExprDAG)
end

for (llvm_version, julia_version) in ((v"14.0.5", v"1.9"),
                                      (v"15.0.6", v"1.10"))
    @info "Generating..." llvm_version julia_version
    temp_prefix() do prefix
    # let prefix = Prefix(mktempdir())
        platform = Pkg.BinaryPlatforms.HostPlatform()
        platform["llvm_version"] = string(llvm_version.major)
        platform["julia_version"] = string(julia_version)
        artifact_paths = setup_dependencies(prefix, dependencies, platform; verbose=true)

        let options = deepcopy(options)
            output_file_path = joinpath(libdir, string(llvm_version.major), options["general"]["output_file_path"])
            isdir(dirname(output_file_path)) || mkpath(dirname(output_file_path))
            options["general"]["output_file_path"] = output_file_path

            include_dir = joinpath(destdir(prefix, platform), "include")
            libmlir_header_dir = joinpath(include_dir, "mlir-c")
            args = Generators.get_default_args()
            push!(args, "-I$include_dir")
            push!(args, "-x")
            push!(args, "c++")

            headers = detect_headers(libmlir_header_dir, args, Dict(), endswith("Python/Interop.h"))
            ctx = create_context(headers, args, options)

            # build without printing so we can do custom rewriting
            build!(ctx, BUILDSTAGE_NO_PRINTING)

            rewrite!(ctx.dag)

            # print
            build!(ctx, BUILDSTAGE_PRINTING_ONLY)
        end

        cleanup_dependencies(prefix, artifact_paths, platform)
    end
end
