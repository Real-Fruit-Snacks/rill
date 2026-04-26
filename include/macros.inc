; macros.inc — common constants and helper macros

%ifndef RILL_MACROS_INC
%define RILL_MACROS_INC

; Standard file descriptors
%define STDIN_FILENO   0
%define STDOUT_FILENO  1
%define STDERR_FILENO  2

; Common exit codes (BSD-style)
%define EXIT_SUCCESS   0
%define EXIT_FAILURE   1
%define EXIT_USAGE   127

%endif
