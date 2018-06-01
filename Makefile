WWW_BROWSER=$(shell \
	{ type xdg-open >/dev/null 2>&1 && echo "xdg-open"; } || \
	{ type open >/dev/null 2>&1 && echo "open"; } \
)

default:
	false

.PHONY: lint
lint:
	luacheck graphql/*.lua \
		test/bench/*.lua \
		test/space/*.lua \
		test/testdata/*.lua \
		test/common/*.lua \
		test/extra/*.lua \
		test/*.lua \
		--no-redefined --no-unused-args

.PHONY: test
test: lint
	virtualenv -p python2.7 ./.env-2.7
	. ./.env-2.7/bin/activate && \
		pip install -r ./test-run/requirements.txt && \
		pip install tarantool && \
		cd test && ./test-run.py

.PHONY: bench
bench: lint
	virtualenv -p python2.7 ./.env-2.7
	. ./.env-2.7/bin/activate && \
		pip install -r ./test-run/requirements.txt && \
		pip install tarantool && \
		cd test && ./test-run.py --long bench/

.PHONY: pure-test
pure-test:
	cd test && ./test-run.py

.PHONY: pure-bench
pure-bench:
	cd test && ./test-run.py --long bench/

.PHONY: clean
clean:
	rm -rf test/var

.PHONY: apidoc
apidoc:
	ldoc -d doc/apidoc graphql --all -f markdown
	# fix navigation panel width
	sed -i -e 's/: 14em;/: 24em;/' doc/apidoc/ldoc.css

.PHONY: serve-apidoc
serve-apidoc: apidoc
	$(WWW_BROWSER) ./doc/apidoc/index.html

.PHONY: demo
demo:
	./demo/demo.lua $(TESTDATA)

.PHONY: rpm
rpm:
	fpm -s dir -t rpm -n tarantool-graphql --rpm-os linux -a noarch  \
		--prefix /usr/share/tarantool \
		--license "BSD 2-Clause License" \
		--rpm-summary "Tarantool graphql module" \
		--url "https://github.com/tarantool/graphql" \
		--vendor "Tarantool team" \
		--depends "tarantool >= 1.9.0" \
		-m "Pavel Yudin <pavel@tarantool.org>" \
		--version `git describe --abbrev=0 || echo "0.2.0"` \
		graphql
