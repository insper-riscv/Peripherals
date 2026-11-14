// SPDX-License-Identifier: Apache-2.0
use std::env;
use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let original = manifest.join("../../c");
    let c_dir = if original.join("rv32_uart.c").is_file() {
        original
    } else {
        manifest.join("../..")
    }
    .canonicalize()
    .expect("UART C driver missing");
    let config = Some(
        env::var_os("RV32_UART_CONFIG_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| c_dir.clone()),
    );
    println!("cargo:rerun-if-env-changed=RV32_UART_CONFIG_DIR");
    let source = c_dir.join("rv32_uart.c");
    let header = c_dir.join("rv32_uart.h");
    let wrapper = manifest.join("wrapper.h");
    let target = env::var("TARGET").unwrap();
    let host = env::var("HOST").unwrap();
    let isa = target_isa(&target, &host);

    println!("cargo:rerun-if-changed={}", source.display());
    println!("cargo:rerun-if-changed={}", header.display());
    println!(
        "cargo:rerun-if-changed={}",
        c_dir.join("rv32_uart_platform.h").display()
    );
    println!("cargo:rerun-if-changed={}", wrapper.display());
    println!("cargo:rerun-if-env-changed=LIBCLANG_PATH");
    println!("cargo:rerun-if-env-changed=CLANG_PATH");

    let mut bindings = bindgen::Builder::default()
        .header(wrapper.to_string_lossy())
        .clang_arg(format!("-I{}", c_dir.display()))
        .clang_arg("-std=c23")
        .clang_arg("-ffreestanding")
        .clang_arg("-fparse-all-comments")
        .allowlist_type("rv32_uart_.*")
        .allowlist_function("rv32_uart_.*")
        .allowlist_var("RV32_UART_.*")
        .prepend_enum_name(false)
        .use_core()
        .size_t_is_usize(true)
        .rust_target(bindgen::RustTarget::stable(85, 0).unwrap())
        .rust_edition(bindgen::RustEdition::Edition2024)
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()));

    if let Some(ref directory) = config {
        assert!(
            directory.join("rv32_uart_platform.h").is_file(),
            "RV32_UART_CONFIG_DIR must contain rv32_uart_platform.h"
        );
        let platform = directory.join("../rv32_platform.h");
        if platform.is_file() {
            println!("cargo:rerun-if-changed={}", platform.display());
        }
        bindings = bindings.clang_arg(format!("-I{}", directory.display()));
        println!(
            "cargo:rerun-if-changed={}",
            directory.join("rv32_uart_platform.h").display()
        );
    }

    // Rust's riscv32i/riscv32im triple names are not Clang target names.
    // Both parsers must use the target ABI, never the build host's pointer size.
    if let Some(isa) = isa {
        bindings = bindings.clang_args([
            "--target=riscv32-unknown-none-elf",
            &format!("-march={isa}"),
            "-mabi=ilp32",
        ]);
    }

    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap());

    bindings
        .generate()
        .expect("UART bindgen failed: install host libclang and check LIBCLANG_PATH")
        .write_to_file(output.join("bindings.rs"))
        .expect("Cannot write generated UART bindings");

    let mut c_build = cc::Build::new();

    if let Some(ref directory) = config {
        c_build.include(directory);
    }
    c_build
        .file(source)
        .include(c_dir)
        .std("c23")
        .flag("-ffreestanding")
        .warnings(true)
        .extra_warnings(true);

    // cc-rs otherwise defaults to RV32IMAC for bare-metal RV32. Match the
    // processor profile explicitly: our RV32I/IM cores do not implement A/C.
    if let Some(isa) = isa {
        c_build.flag(format!("-march={isa}")).flag("-mabi=ilp32");
    }

    // Clang supports both host and bare-metal RV32 without an SDK sysroot.
    // Respect cc-rs overrides when a caller explicitly selects another compiler.
    let underscored_target = target.replace('-', "_");
    let compiler_overridden = [
        format!("CC_{target}"),
        format!("CC_{underscored_target}"),
        if target == host {
            "HOST_CC"
        } else {
            "TARGET_CC"
        }
        .to_owned(),
        "CC".to_owned(),
    ]
    .iter()
    .any(|name| env::var_os(name).is_some());

    if !compiler_overridden {
        c_build.compiler(env::var_os("CLANG_PATH").unwrap_or_else(|| "clang".into()));
    }

    // cc-rs emits Cargo link-search/link-lib directives for this static archive.
    c_build.compile("rv32_uart");
}

fn target_isa(target: &str, host: &str) -> Option<&'static str> {
    match target {
        "riscv32i-unknown-none-elf" => Some("rv32i"),
        "riscv32im-unknown-none-elf" => Some("rv32im"),
        _ if target == host => None,
        _ => panic!("Unsupported cross target {target}; use RV32I, RV32IM or native host tests"),
    }
}
