PROGNM ?= archlinux-repro
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SHRDIR ?= $(PREFIX)/share
DOCDIR ?= $(PREFIX)/share/doc
MANDIR ?= $(PREFIX)/share/man
CONFDIR ?= /etc
MANS = $(basename $(wildcard docs/*.txt))

TAG = $(shell git describe --abbrev=0 --tags)

all: man repro
man: $(MANS)
$(MANS):

docs/repro.%: docs/repro.%.txt docs/asciidoc.conf
	a2x --no-xmllint --asciidoc-opts="-f docs/asciidoc.conf" -d manpage -f manpage -D docs $<

repro: repro.in
	m4 -DREPRO_VERSION=$(TAG) -DREPRO_CONFIG_DIR=$(CONFDIR)/$(PROGNM) $< >$@
	chmod 755 $@

.PHONY: install
install: repro man
	install -Dm755 repro $(DESTDIR)$(BINDIR)/$(PROGNM)
	ln -s $(PROGNM) $(DESTDIR)$(BINDIR)/repro
	install -Dm755 buildinfo -t $(DESTDIR)$(BINDIR)
	install -Dm644 examples/*   -t $(DESTDIR)$(DOCDIR)/$(PROGNM)
	for manfile in $(MANS); do \
		install -Dm644 $$manfile -t $(DESTDIR)$(MANDIR)/man$${manfile##*.}; \
	done;
	install -Dm644 LICENSE -t $(DESTDIR)$(SHRDIR)/licenses/$(PROGNM)

.PHONY: uninstall
uninstall:
	rm $(DESTDIR)$(BINDIR)/repro
	rm $(DESTDIR)$(BINDIR)/buildinfo
	rm -rf $(DESTDIR)$(DOCDIR)/$(PROGNM)
	for manfile in $(MANS); do \
		rm $(DESTDIR)$(MANDIR)/man$${manfile##*.}/$${manfile##*/}; \
	done;
	rm -rf $(DESTDIR)$(SHRDIR)/licenses/$(PROGNM)

.PHONY: clean
clean:
	rm -f repro $(MANS)

.PHONY: tag
tag:
	git describe --exact-match >/dev/null 2>&1 || git tag -s $(shell date +%Y%m%d)
	git push --tags

.PHONY: release
release:
	mkdir -p releases
	git -c tar.tar.gz.command='gzip -cn' archive --prefix=${PROGNM}-${TAG}/ -o releases/${PROGNM}-${TAG}.tar.gz ${TAG}
	gpg --detach-sign -o releases/${PROGNM}-${TAG}.tar.gz.sig releases/${PROGNM}-${TAG}.tar.gz
	hub release create -m "Release: ${TAG}" -a releases/${PROGNM}-${TAG}.tar.gz.sig -a releases/${PROGNM}-${TAG}.tar.gz ${TAG}
