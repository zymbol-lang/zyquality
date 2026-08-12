# Build with ocamlopt directly — no dune, no opam switch, no external
# libraries.  Same approach as zyml; `unix` ships with the compiler.

OCAMLOPT ?= ocamlopt
OCAMLFLAGS = -O3 -w +a-4-9-40-41-42-44-45-70 -I src -I +unix
LIBS = unix.cmxa

# Order matters: this is the dependency chain.
MODULES = toml rx compare corpus engine consensus golden suite report main
CMX = $(addprefix src/,$(addsuffix .cmx,$(MODULES)))
BIN = zyq

.PHONY: all clean engines consensus expect reject suite check selftest

all: $(BIN)

$(BIN): $(CMX)
	$(OCAMLOPT) $(OCAMLFLAGS) $(LIBS) $(CMX) -o $(BIN)

src/%.cmx: src/%.ml
	$(OCAMLOPT) $(OCAMLFLAGS) -c $<

src/toml.cmx: src/toml.ml
src/rx.cmx: src/rx.ml
src/compare.cmx: src/compare.ml
src/corpus.cmx: src/corpus.ml src/toml.cmx src/rx.cmx
src/engine.cmx: src/engine.ml src/toml.cmx
src/consensus.cmx: src/consensus.ml src/engine.cmx src/compare.cmx src/corpus.cmx
src/golden.cmx: src/golden.ml src/engine.cmx src/corpus.cmx
src/suite.cmx: src/suite.ml src/toml.cmx
src/report.cmx: src/report.ml src/consensus.cmx src/engine.cmx src/golden.cmx
src/main.cmx: src/main.ml src/consensus.cmx src/report.cmx src/golden.cmx src/corpus.cmx src/suite.cmx

engines: $(BIN)
	@./$(BIN) engines

consensus: $(BIN)
	@./$(BIN) consensus

expect: $(BIN)
	@./$(BIN) expect

reject: $(BIN)
	@./$(BIN) reject

# The whole gate, one verdict.  This is what every other repository's test
# script delegates to.
suite: $(BIN)
	@./$(BIN) suite

# zyq's own tests: the matcher, the globs and the config reader, checked
# against cases whose answer is known by inspection.  A bench that grades 588
# files has to be graded itself — the two harness defects found while producing
# the first consensus numbers (a reversed argv, a missing module resolver) both
# inflated the divergence count and neither was visible in the output.
selftest: $(BIN)
	@./$(BIN) selftest

# Corpus hygiene: rules that match no file, files no engine can run, goldens
# with no program.
check: $(BIN)
	@./$(BIN) audit

clean:
	rm -f src/*.cmx src/*.cmi src/*.o $(BIN)
