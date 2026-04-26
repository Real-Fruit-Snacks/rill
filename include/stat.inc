; stat.inc — offsets and constants for x86_64 Linux struct stat.
;
; Layout (struct stat from sys/stat.h on x86_64 glibc / kernel):
;
;   off  size  field
;     0    8   st_dev
;     8    8   st_ino
;    16    8   st_nlink
;    24    4   st_mode
;    28    4   st_uid
;    32    4   st_gid
;    36    4   __pad0
;    40    8   st_rdev
;    48    8   st_size
;    56    8   st_blksize
;    64    8   st_blocks
;    72   16   st_atim   (sec at +72, nsec at +80)
;    88   16   st_mtim   (sec at +88, nsec at +96)
;   104   16   st_ctim   (sec at +104, nsec at +112)
;   120   24   __unused[3]
;   ----------
;   total: 144 bytes

%ifndef RILL_STAT_INC
%define RILL_STAT_INC

%define STATBUF_SIZE   144

%define ST_DEV         0
%define ST_INO         8
%define ST_NLINK      16
%define ST_MODE       24
%define ST_UID        28
%define ST_GID        32
%define ST_RDEV       40
%define ST_SIZE       48
%define ST_BLKSIZE    56
%define ST_BLOCKS     64
%define ST_ATIME      72
%define ST_MTIME      88
%define ST_CTIME     104

; File type bits in st_mode.
%define S_IFMT     0o170000
%define S_IFSOCK   0o140000
%define S_IFLNK    0o120000
%define S_IFREG    0o100000
%define S_IFBLK    0o060000
%define S_IFDIR    0o040000
%define S_IFCHR    0o020000
%define S_IFIFO    0o010000

; Permission bits.
%define S_ISUID    0o004000
%define S_ISGID    0o002000
%define S_ISVTX    0o001000

%endif
