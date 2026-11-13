# Build SmallLinks from the repository root. See INSTALL.md for installation.

BUILD = opam exec -- dune build --build-dir=_build
LINKS_EXE = _build/default/bin/links.exe
RELEASE_PKGS = links

.DEFAULT_GOAL := all
.PHONY: all all-release all-ci
all: PROFILE = dev
all-release: PROFILE = release
all-ci: PROFILE = ci
all all-release all-ci: links linx
	$(BUILD) --profile=$(PROFILE) @install

links: Makefile
	@printf '%s\n' '#!/usr/bin/env sh' 'exec "$$(dirname "$$0")/$(LINKS_EXE)" "$$@"' > $@
	@chmod +x $@

linx: links
	ln -fs links linx

# Use the existing build when testing, including one built with the CI profile.
$(LINKS_EXE):
	$(BUILD) --profile=dev @install

.PHONY: tests
tests: links $(LINKS_EXE)
	CAMLRUNPARAM= OCAMLRUNPARAM= ./run-tests

# Cleans the project directory.
.PHONY: clean
clean:
	opam exec dune -- clean
	rm -rf *.install
	rm -rf links linx
	rm -rf doc/_build

.PHONY: clean-doc
clean-doc:
	rm -rf doc/_build

# Applies some ad-hoc checks on the source code.
.PHONY: rule-check
rule-check: tools/rule-check
	@echo "Applying rule check"
	@tools/rule-check

doc/_build/html:
	make -C doc html

.PHONY: doc
doc : doc/_build/html

.PHONY: open-doc
open-doc: doc/_build/html
	xdg-open doc/_build/html/index.html

# Release Links
opam-release:
	opam exec dune-release -- tag
	opam exec dune-release -- distrib -p $(RELEASE_PKGS)
	opam exec dune-release -- publish -p $(RELEASE_PKGS) distrib
	opam exec dune-release -- opam -p $(RELEASE_PKGS) pkg
	opam exec dune-release -- opam -p $(RELEASE_PKGS) submit
