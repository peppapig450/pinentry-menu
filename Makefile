PREFIX ?= /usr
BINDIR := $(PREFIX)/bin
SCRIPT := src/pinentry-menu.sh
TARGET := pinentry-menu

all:
	@true

install:
	install -Dm755 $(SCRIPT) $(DESTDIR)$(BINDIR)/$(TARGET)

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/$(TARGET)

.PHONY: all install uninstall
