; syscalls.inc — x86_64 Linux syscall numbers
;
; Source: arch/x86/entry/syscalls/syscall_64.tbl in the Linux kernel.
; Only syscalls actually referenced from rill are listed here; add new ones
; as applets need them.

%ifndef RILL_SYSCALLS_INC
%define RILL_SYSCALLS_INC

%define SYS_read         0
%define SYS_write        1
%define SYS_open         2
%define SYS_close        3
%define SYS_stat         4
%define SYS_fstat        5
%define SYS_lstat        6
%define SYS_lseek        8
%define SYS_mmap         9
%define SYS_brk          12
%define SYS_access       21
%define SYS_pipe         22
%define SYS_dup          32
%define SYS_dup2         33
%define SYS_nanosleep    35
%define SYS_getpid       39
%define SYS_exit         60
%define SYS_kill         62
%define SYS_uname        63
%define SYS_getcwd       79
%define SYS_rename       82
%define SYS_mkdir        83
%define SYS_rmdir        84
%define SYS_creat        85
%define SYS_link         86
%define SYS_unlink       87
%define SYS_symlink      88
%define SYS_readlink     89
%define SYS_chmod        90
%define SYS_fchmod       91
%define SYS_chown        92
%define SYS_fchown       93
%define SYS_lchown       94
%define SYS_umask        95
%define SYS_getuid       102
%define SYS_getgid       104
%define SYS_geteuid      107
%define SYS_getegid      108
%define SYS_getdents64   217
%define SYS_time         201
%define SYS_clock_gettime 228
%define SYS_exit_group   231
%define SYS_openat       257
%define SYS_unlinkat     263
%define SYS_renameat     264
%define SYS_utimensat    280

%endif
