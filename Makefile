#
# Makefile for the Links Programming Language.
#

# This file contains instructions for building a bleeding-edge version
# of Links in release or development mode.

# LATEST STABLE RELEASE
# =====================
# To install the latest stable release of Links please see the INSTALL
# file.

# To build the bleeding-edge version of Links please refer to the
# instructions below.

# DEVELOPMENT
# ===========
# By default the build rule `all' attempts to build the latest
# development version of Links.
# $ make all
# The `nc' and `no-db' targets are aliases for `all'.

# RELEASE
# =======
# To build Links in release mode use the following command
# $ make all-release
# This rule builds every artefact which is part of a release.


# Project root and build directory
ROOT:=$(shell dirname $(firstword $(MAKEFILE_LIST)))
BUILD_DIR:=$(ROOT)/_build

# The build command and some standard build system flags
BUILD=opam exec dune -- build
COMMON_FLAGS=--build-dir=$(BUILD_DIR)
DEV_FLAGS=$(COMMON_FLAGS) --profile=dev
REL_FLAGS=$(COMMON_FLAGS) --profile=release
CI_FLAGS=$(COMMON_FLAGS) --profile=ci
# List of packages that we currently release
RELEASE_PKGS:=links

# Build rules.

# The default is to build everything in development mode.
.DEFAULT_GOAL:= all
.PHONY: all
all: build-dev-all create-startup-script

# Builds everything in release mode.
.PHONY: all-release
all-release: build-release-all create-startup-script

# Builds everything in continuous integration mode.
.PHONY: all-ci
all-ci: build-ci-all create-startup-script

# Legacy rule to remain backwards compatible with the OCamlMakefile
# interface.
.PHONY: nc
nc: all

.PHONY: no-db
no-db: all

# Creates a thin shell script, which executes the built Links
# executable in a pre-configured environment.
ABS_BUILD_DIR=$(BUILD_DIR)
.PHONY: create-startup-script
create-startup-script:
	@echo "#!/usr/bin/env sh" > links
	@# This path resolution scheme may depend on BASH semantics.
	$(eval ABS_BUILD_DIR=$(shell cd $(BUILD_DIR) ; pwd -P))
	@# This is an attempt to put in a safe guard
	@# If the above resolution fails to yield an existing path then fall back to the relative path in BUILD_DIR.
	$(eval ABS_BUILD_DIR:=$(shell test -d $(ABS_BUILD_DIR) && echo "$(ABS_BUILD_DIR)" || echo "$(BUILD_DIR)"))
	@echo "$(ABS_BUILD_DIR)/default/bin/links.exe \"\$$@\"" >> links
	@chmod +x links
	ln -fs links linx

# Invokes `dune' to build everything in continuous integration mode.
.PHONY: build-ci-all
build-ci-all: dune dune-project
	$(BUILD) $(CI_FLAGS) @install

# Invokes `dune' to build everything in development mode.
.PHONY: build-dev-all
build-dev-all: dune dune-project
	$(BUILD) $(DEV_FLAGS) @install

# Invokes `dune' to build everything in release mode.
.PHONY: build-release-all
build-release-all: dune dune-project
	$(BUILD) $(REL_FLAGS) @install


# Auxiliary rule used by `opam install` to build Links
.PHONY: opam-build-links.opam
opam-build-links.opam: links.opam
	$(shell LINKS_BUILT_BY_OPAM=1 opam exec dune -- build -p links)

# Runs the test suite. We reset the variables CAMLRUNPARAM and
# OCAMLRUNPARAM, because some of the tests are sensitive to the
# printing of stack traces.
.PHONY: tests
tests: links
	$(eval OCAMLRUNPARAM="")
	$(eval CAMLRUNPARAM="")
	./run-tests

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
