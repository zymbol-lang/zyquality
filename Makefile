# Build with ocamlopt directly — no dune, no opam switch, no external
# libraries.  Same approach as zyml; `unix` ships with the compiler.

OCAMLOPT ?= ocamlopt
OCAMLFLAGS = -O3 -w +a-4-9-40-41-42-44-45-70 -I src -I +unix
LIBS = unix.cmxa

# Order matters: this is the dependency chain.
MODULES = compare engine consensus report main
CMX = $(addprefix src/,$(addsuffix .cmx,$(MODULES)))
BIN = zyq

.PHONY: all clean engines consensus check

all: $(BIN)

$(BIN): $(CMX)
	$(OCAMLOPT) $(OCAMLFLAGS) $(LIBS) $(CMX) -o $(BIN)

src/%.cmx: src/%.ml
	$(OCAMLOPT) $(OCAMLFLAGS) -c $<

src/compare.cmx: src/compare.ml
src/engine.cmx: src/engine.ml
src/consensus.cmx: src/consensus.ml src/engine.cmx src/compare.cmx
src/report.cmx: src/report.ml src/consensus.cmx src/engine.cmx
src/main.cmx: src/main.ml src/consensus.cmx src/report.cmx

engines: $(BIN)
	@./$(BIN) engines

consensus: $(BIN)
	@./$(BIN) consensus

clean:
	rm -f src/*.cmx src/*.cmi src/*.o $(BIN)
