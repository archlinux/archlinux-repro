PROGNM = devtools-repro
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SHRDIR ?= $(PREFIX)/share
DOCDIR ?= $(PREFIX)/share/doc
MANDIR ?= $(PREFIX)/share/man
CONFDIR ?= /etc
MANS = $(basename $(wildcard docs/*.txt))

all: man repro
man: $(MANS)
$(MANS):

docs/repro.%: docs/repro.%.txt docs/asciidoc.conf
	a2x --no-xmllint --asciidoc-opts="-f docs/asciidoc.conf" -d manpage -f manpage -D docs $<

repro: repro.in
	m4 -DREPRO_CONFIG_DIR=$(CONFDIR)/$(PROGNM) $< >$@

install: repro man
	install -Dm755 repro -t $(DESTDIR)$(BINDIR)
	install -Dm755 buildinfo -t $(DESTDIR)$(BINDIR)
	install -Dm644 conf/*.conf -t $(DESTDIR)$(CONFDIR)/$(PROGNM)
	install -Dm644 conf/profiles/*.conf -t $(DESTDIR)$(CONFDIR)/$(PROGNM)/profiles
	install -Dm644 examples/*   -t $(DESTDIR)$(DOCDIR)/$(PROGNM)
	for manfile in $(MANS); do \
		install -Dm644 $$manfile -t $(DESTDIR)$(MANDIR)/man$${manfile##*.}; \
	done;
	install -Dm644 LICENSE -t $(DESTDIR)$(SHRDIR)/licenses/$(PROGNM)

clean:
	rm -f repro $(MANS)
