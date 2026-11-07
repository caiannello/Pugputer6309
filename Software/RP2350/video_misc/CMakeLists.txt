# The Pugputer 6309 video card's firmware (see README.md). Builds vidcard.uf2 for the Olimex
# RP2350-PICO2-XXL with the Pico SDK.
cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.3.1)
set(toolchainVersion 15_2_Rel1)
set(picotoolVersion 2.3.1)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================

set(PICO_BOARD olimex_rp2350_xxl CACHE STRING "Board type")

include(pico_sdk_import.cmake)
project(vidcard C CXX ASM)
pico_sdk_init()

# The card itself: the same C the emulator runs (Pugputer6309_Emulator's vidcard/core).
set(CORE ${CMAKE_CURRENT_LIST_DIR}/core)

add_executable(vidcard
    src/main.c
    src/card.c
    src/bus.c
    src/dvi.c
    src/sd.c
    src/blockdev.c
    src/bench.c
    src/usbhost.c
    ${CORE}/vc.c
    ${CORE}/vc_font.c
)
set_source_files_properties(src/main.c src/card.c src/bus.c src/dvi.c src/sd.c src/blockdev.c src/bench.c src/usbhost.c ${CORE}/vc.c
    PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra")
pico_generate_pio_header(vidcard ${CMAKE_CURRENT_LIST_DIR}/src/bus.pio)
target_include_directories(vidcard PRIVATE src ${CORE})
target_compile_definitions(vidcard PRIVATE
    VC_ATOMIC_FLAGS=1                  # the interrupt flags change from both cores (vc.c)
    PICO_PSRAM_CS_PIN=8                # the board's 8MB PSRAM, set up by the SDK at start
    PICO_PSRAM_SIZE_BYTES=0x800000
)
# Bring-up diagnostics (bus.c): -DBUS_DIAG=1 keeps the level shifters off,
# -DBUS_DIAG=2 turns them on but never drives D0-D7.
if(DEFINED BUS_DIAG)
    target_compile_definitions(vidcard PRIVATE BUS_DIAG=${BUS_DIAG})
endif()
# -DVIDCARD_DIAG=1: a status report once a second on the UART (and row 3 of the screen):
# the bus accesses seen, by register, the resets, and whether the picture is running.
if(DEFINED VIDCARD_DIAG)
    target_compile_definitions(vidcard PRIVATE VIDCARD_DIAG=${VIDCARD_DIAG})
endif()
target_link_libraries(vidcard
    pico_stdlib
    pico_multicore
    hardware_clocks
    hardware_pll
    hardware_dma
    hardware_pio
    hardware_psram
    hardware_spi
    hardware_vreg
    tinyusb_host
)
# Everything runs from SRAM (copied there from flash at start): the bus interrupt and
# the picture can't wait on the flash, which also shares its cache with the PSRAM.
pico_set_binary_type(vidcard copy_to_ram)
pico_enable_stdio_uart(vidcard 1)
pico_enable_stdio_usb(vidcard 0)
pico_add_extra_outputs(vidcard)
