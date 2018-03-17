PROGNM = devtools-repro
PREFIX ?= /usr
SHRDIR ?= $(PREFIX)/share
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
DOCSDIR ?= $(SHRDIR)/doc
CONFDIR ?= /etc

.PHONY: install

repro: repro.in
	m4 -DREPRO_CONFIG_DIR=$(CONFDIR)/$(PROGNM) $< >$@

install: repro
	@install -Dm755 repro	-t $(DESTDIR)$(BINDIR)
	@install -Dm644 conf/*   -t $(DESTDIR)$(CONFDIR)/$(PROGNM)
	@install -Dm644 docs/*   -t $(DESTDIR)$(DOCSDIR)/$(PROGNM)
	@install -Dm644 LICENSE -t $(DESTDIR)$(SHRDIR)/licenses/$(PROGNM)
