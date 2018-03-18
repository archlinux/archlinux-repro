PROGNM = devtools-repro
PREFIX ?= /usr
SHRDIR ?= $(PREFIX)/share
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
DOCSDIR ?= $(SHRDIR)/doc
CONFDIR ?= /etc

all: man repro
man: docs/repro.8 docs/repro.conf.5

repro.%:
	a2x --no-xmllint --asciidoc-opts="-f docs/asciidoc.conf" -d manpage -f manpage -D docs $@.txt

repro: repro.in
	m4 -DREPRO_CONFIG_DIR=$(CONFDIR)/$(PROGNM) $< >$@

install: repro man
	@install -Dm755 repro	-t $(DESTDIR)$(BINDIR)
	@install -Dm644 conf/*   -t $(DESTDIR)$(CONFDIR)/$(PROGNM)
	@install -Dm644 examples/*   -t $(DESTDIR)$(SHRDIR)/$(PROGNM)
	@install -Dm644 docs/repro.8   -t $(DESTDIR)$(SHRDIR)/man/man8
	@install -Dm644 docs/repro.conf.5   -t $(DESTDIR)$(SHRDIR)/man/man5
	@install -Dm644 LICENSE -t $(DESTDIR)$(SHRDIR)/licenses/$(PROGNM)
