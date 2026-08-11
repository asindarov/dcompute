module dcompute.driver.metal.program;
import dcompute.driver.metal.device;
import dcompute.driver.metal.kernel;
import objc;
import foundation;
import core.stdc.stdio;
import std.string;
import std.path;
import metal.library;
import metal.device;
import llvm_downgrader.lib;
import std.process;
import std.typecons: Nullable, nullable;
struct Program
{
    MTLLibrary metalLibrary;

    Kernel!void getKernelByName(immutable(char)* name)
    {
        auto kName = fromStringz(name);

        auto kNameInNSString = NSString.create(kName);

        auto kernelFunction = metalLibrary.newFunctionWithName(kNameInNSString);

        if (kernelFunction is null)
        {
            printf("Error: Could not find kernel function %s in library.\n", name);
            assert(0);
        }

        return Kernel!void(kernelFunction);
    }

    Kernel!(typeof(k)) getKernel(alias k)()
    {
        return cast(typeof(return)) getKernelByName(k.mangleof.ptr);
    }

    static Program fromFile(Device device, string path)
    {
        auto downgraded_llvm_bitcode_path = downgrade_llvm_bitcode(path);

        if (downgraded_llvm_bitcode_path.isNull) {
            printf("Error occured while downgrading given air\n");
        }

        auto compiled_metallib_path = metallib_as(downgraded_llvm_bitcode_path.get());

        if (compiled_metallib_path.isNull) {
            printf("Error occured while compiling the downgraded air to metallib binary\n");
        }

        NSError error;
        auto nsPath = NSString.create(absolutePath(compiled_metallib_path.get()));

        auto library = device.mtlDevice.newLibrary(NSURL.fromPath(nsPath), error);

        if (library is null)
        {
            printf("Error loading .metallib: %s\n", error.localizedDescription().ptr);
            assert(0);
        }

        return Program(library);
    }

    static Nullable!string metallib_as(string air_bit_code_path) {
        string absInputPath = absolutePath(air_bit_code_path);

        string absOutputPath = absInputPath.setExtension("metallib");

        auto result = execute([
                "xcrun",
                "-sdk", "macosx",
                "metallib",
                absInputPath,
                "-o", absOutputPath
            ]);

        if (result.status != 0) {
            printf("Apple metallib tool failed:\n%s\n", result.output.ptr);
            return Nullable!string.init;
        }

        return nullable(absOutputPath);
    }

    static Nullable!string downgrade_llvm_bitcode(string air_bit_code_path) {
        string absInputPath = absolutePath(air_bit_code_path);
        string absOutputPath = absInputPath.setExtension("bc");
        return llvm_downgrade( (string downgrader) {

            auto result = execute([
                downgrader,
                "-o",  absOutputPath,
                absInputPath,
                "--bitcode-version=14.0"
            ]);

            if (result.status != 0) {
                return Nullable!string.init;
            }

            return nullable(absOutputPath);
        } );
    }
    __gshared static Program globalProgram;

    void unload()
    {
        metalLibrary = null;
    }
}
