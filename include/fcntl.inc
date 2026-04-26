; fcntl.inc — open(2) flags and AT_* sentinels.

%ifndef RILL_FCNTL_INC
%define RILL_FCNTL_INC

%define O_RDONLY      0o
%define O_WRONLY      1o
%define O_RDWR        2o
%define O_CREAT      100o
%define O_EXCL       200o
%define O_NOCTTY     400o
%define O_TRUNC     1000o
%define O_APPEND    2000o
%define O_NOFOLLOW  400000o
%define O_DIRECTORY 200000o

; AT_FDCWD is -100 — the conventional sentinel for *at() calls indicating
; that relative paths should be resolved against the current working dir.
%define AT_FDCWD              -100
%define AT_SYMLINK_NOFOLLOW   0x100
%define AT_REMOVEDIR          0x200

%endif
