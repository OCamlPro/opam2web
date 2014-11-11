.PHONY: all build install clean

all: build

build:
	cd src && $(MAKE)
	cp src/search.js ext/js/

install:
	cd src && $(MAKE) install

clean:
	cd src && $(MAKE) clean

.PHONY: test-prepare
test-prepare:
	rm -rf www
	mkdir -p www/content/doc www/content/blog
	cd www && \
	cp -r ../content . && \
	cp -r ../../opam.wiki/* content/doc/ && \
	cp -r ../../opam-blog/* content/blog/

test: build test-prepare
	cd www && \
	../src/_build/opam2web.native --content content path:. && \
	cp -r -L ../ext . && \
	xdg-open index.html

fulltest: build test-prepare
	cd www && \
	git clone git@github.com:ocaml/opam-repository -b master && \
	../src/_build/opam2web.native --content content path:opam-repository && \
	cp -r -L ../ext . && \
	xdg-open index.html
