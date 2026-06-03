# asm-systems-archive

A comprehensive master repository of low-level systems engineering, tracking decades of x86_64, x86_32, and legacy assembly architectures. This vault spans foundational low-overhead routines, hardware-level interface layers, and direct Linux kernel syscall orchestration, serving as a pristine reference library for zero-dependency assembly programming.

---

## Core Library Categories

### 1. Data Conversion Engine (`library/convert/`)
Highly optimized, hardware-level numeric type transformations handling multi-precision allocations across `byte`, `word`, `dword`, and `qword` registers:
* **BCD Arithmetic:** Dual-direction Binary Coded Decimal transformations (`bcd2bin`, `bin2bcd`) matching vintage hardware parsing configurations.
* **ASCII Stream Matrix:** Direct binary-to-hexadecimal ASCII converters engineered for headerless diagnostic readouts.

### 2. Native Inter-Process Communication & System Control (`library/system/`)
Pure System V ABI-compliant hooks interfacing directly with the Linux kernel without linking against standard C runtimes (`libc`):
* **IPC Key Generation:** Native `ftok` implementation handling system-wide token construction.
* **Resource Allocation:** Direct kernel querying for virtual page structures (`pagesize`) and microsecond execution delays (`sleep`).

### 3. High-Throughput Matrix & Vector Mathematics (`tui/avx/`)
Advanced SIMD vectorization pipelines leveraging the processor's widest floating-point registers for high-performance computing arrays:
* **AVX / AVX2 Blocks:** 256-bit wide packed parallel register routines.
* **AVX-512 Instruction Sets:** 512-bit hyper-scale register execution templates for math intensive algorithmic solvers.
### 4. Direct Graphic & Web Interfaces
* **Low-Level Windowing (`examples/gui/`):** Event-loop mapping and memory handling utilizing direct X11 protocols and native GTK callback structures.
* **Assembly Web CGI (`tui/cgi/`):** Minimalist Common Gateway Interface handlers optimized to parse POST variables and manipulate JSON documents straight out of network sockets with zero memory footprints.

---

## Architecture & Tools Reference

* **Assembler Variant:** NASM (Netwide Assembler) targeting `elf64` / `elf32` objects.
* **Linking Target:** Native Linux GNU Linker (`ld`) configured for strict non-PIE stack alignment layout rules.
* **Historical Foundation:** Incorporates classic low-level optimization manual strategies from Agner Fog and complete structural maps for bare-metal x86 bootloaders.

---

## Project Status

This repository is maintained as an active personal library and historical archive. Development focuses strictly on absolute low-overhead portability, stack alignment validation, and zero-dependency low-level optimization templates.

---

## License

All custom structural components inside this archive are open for application engineering under Apache 2.0 tracking terms.
