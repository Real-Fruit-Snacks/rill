/* linker.ld — minimal static ELF layout for rill.
 *
 * Two PT_LOAD segments: one r-x for code+rodata, one rw- for data+bss.
 * Linker-emitted noise (.note, .comment, .eh_frame) is discarded so the
 * binary contains only what we wrote.
 */

ENTRY(_start)

PHDRS {
    text PT_LOAD FILEHDR PHDRS FLAGS(5);    /* r-x */
    data PT_LOAD                FLAGS(6);   /* rw- */
}

SECTIONS {
    . = 0x400000 + SIZEOF_HEADERS;

    .text : {
        *(.text)
        *(.text.*)
    } :text

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    } :text

    . = ALIGN(0x1000);

    .data : {
        *(.data)
        *(.data.*)
    } :data

    .bss : {
        *(.bss)
        *(.bss.*)
    } :data

    /DISCARD/ : {
        *(.note.*)
        *(.comment)
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.debug_*)
    }
}
