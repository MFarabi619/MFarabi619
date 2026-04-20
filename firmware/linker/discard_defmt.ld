.defmt 0 (NOLOAD) : {
    *(.defmt*)
}

/DISCARD/ : {
    *(.note.GNU-stack)
}
