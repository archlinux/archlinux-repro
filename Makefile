PROGNM = devtools-repro
PREFIX ?= /usr
SHRDIR ?= $(PREFIX)/share
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib

.PHONY: install

repro: repro.in
	m4 -DREPRO_LIB_DIR=$(LIBDIR)/$(PROGNM) $< >$@

install: repro
	@install -Dm755 repro	-t $(DESTDIR)$(BINDIR)
	@install -Dm755 lib/*   -t $(DESTDIR)$(LIBDIR)/$(PROGNM)
	@install -Dm644 LICENSE -t $(DESTDIR)$(SHRDIR)/licenses/$(PROGNM)
