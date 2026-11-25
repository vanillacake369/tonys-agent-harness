//go:build darwin

package core

import (
	"os"
	"syscall"
	"unsafe"
)

func terminalInput() bool {
	var term syscall.Termios
	_, _, err := syscall.Syscall(syscall.SYS_IOCTL, os.Stdin.Fd(), syscall.TIOCGETA, uintptr(unsafe.Pointer(&term)))
	return err == 0
}
