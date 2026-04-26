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
%define SYS_pipe         22
%define SYS_dup          32
%define SYS_dup2         33
%define SYS_nanosleep    35
%define SYS_getpid       39
%define SYS_exit         60
%define SYS_kill         62
%define SYS_uname        63
%define SYS_getcwd       79
%define SYS_readlink     89
%define SYS_getuid       102
%define SYS_getgid       104
%define SYS_geteuid      107
%define SYS_getegid      108
%define SYS_exit_group   231
%define SYS_openat       257

%endif
