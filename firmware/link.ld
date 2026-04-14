MEMORY {
    SRAM (rwx) : ORIGIN = 0x08000000, LENGTH = 8K
}

SECTIONS {
    .text : {
        *(.text)
    } > SRAM
}
