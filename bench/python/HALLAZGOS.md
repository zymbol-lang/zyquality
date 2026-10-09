# ZyBench — hallazgos

> **Qué es esto.** El log de hallazgos de ZyBench, la medición de la VM de Zymbol contra Python con los programas de `zyquality/bench/`, en la forma canónica que pide
> `zymbol-design/LDV.md` § 5.2: un fichero `HALLAZGOS.md`, cuatro secciones
> (`BUG` / `GAP` / `ERROR` / `IDEA`), una tabla resumen e identificadores con el alcance del
> proyecto desde la primera entrada, en **una sola secuencia** para los cuatro tipos.
>
> **Qué es este proyecto.** Un banco de medida: ports a Python de 9 de los 12 programas de
> `zyquality/bench/` (65 mediciones, el resultado coincide con el de Zymbol en las 65), un `measure.py`
> que los corre contra cualquier binario, y el perfilado y la optimización de lo que la medición
> señala. **No nació de una aplicación sino de preguntar cuánto pesa el lenguaje en la velocidad** y
> de validar la frase del manual sobre Python; por eso es un proyecto de **medición** y no de uso, y
> todos sus hallazgos salieron de los benchmarks (**2026-10-04** a **2026-10-07**), no de ninguna aplicación.
>
> **Estado.** Cada entrada dice el suyo. **Nada se cierra con este documento:** el autor decide por
> hallazgo si implementa, aplaza o rechaza. Este proyecto **no está en la puerta**
> (`zyquality/project/apps.toml`) ni indexado en `LDV.md` § 5.1: eso también lo decide el autor.
>
> **Cómo se midió, para que se pueda repetir.** Los tiempos son medianas de 2 a 5 ejecuciones. Las
> mediciones de la VM, salvo que se diga otra cosa, son del binario publicado v0.0.9 (opt-level 3) o de
> compilaciones propias de la rama v0.0.10 (`820a60a`) con **opt-level 1 y sin LTO**, más lentas que el
> perfil release del repositorio: la proporción entre dos compilaciones iguales vale, el milisegundo
> absoluto no. Donde se puede, se da el número de **instrucciones** (callgrind), que no varía entre
> ejecuciones. `T::elapsed` imprime milisegundos enteros: por debajo de ~10 ms es ruido, y una razón
> contra un Python que marca 0 o 1 ms es una cota, no un valor. Los parches que acompañan a BEN-001 y
> BEN-002 están aplicados **solo en una copia de trabajo**; ninguno está integrado.

---

## Resumen

| ID | Tipo | Módulo | Qué | Motores | Estado |
|----|------|--------|-----|---------|--------|
| [BUG-BEN-001](#bug-ben-001) | BUG | `zymbol-vm`, `zymbol-interpreter` | `$^ (a, b -> …)` es una burbuja sin salida anticipada: n(n−1)/2 llamadas, siempre | `zytw` y `zyvm` (dos copias) | **PROPUESTO** 2026-10-04 — `ordenar_comparador.patch` |
| [IDEA-BEN-002](#idea-ben-002) | IDEA | `zymbol-vm` | la mitad del coste de una llamada era preparar y soltar el marco de registros | `zyvm` | **PROPUESTO** 2026-10-07 — `vm_llamadas.patch`; parte de `ZYVM-010` |
| [IDEA-BEN-003](#idea-ben-003) | IDEA | `zyquality/bench/` | la VM gana a Python en 4 de 16 pruebas generales y en 0 de 14 de texto | medición | **MEDIDO** 2026-10-04 a 2026-10-07 |
| [ERROR-BEN-004](#error-ben-004) | ERROR | `MANUAL.md` línea 121 | «~1.1–1.5× más rápida que Python en la mayoría de las cargas» no se sostiene fuera de los bucles de enteros | medición | **ABIERTO** |

---

## BUG

### BUG-BEN-001

**La ordenación con comparador propio hace siempre n(n−1)/2 llamadas a la lambda:
es una burbuja sin salida anticipada, y está escrita dos veces.**

Encontrado el **2026-10-04** al portar `bench_text` y `bench_hof` a Python. En
`stress_v2/bench_hof`, `H8_sort_custom` (500 elementos, 3 veces) tardaba **38 ms** en la VM
publicada y **300 ms** en el intérprete directo, contra menos de 0,5 ms en Python. Escalado
con un comparador `p < q` sobre enteros aleatorios (VM publicada v0.0.9, mediana de 3):

| n | tiempo | × al duplicar n |
|---|---:|---:|
| 1 000 | 49 ms | |
| 2 000 | 189 ms | 3,9 |
| 4 000 | 749 ms | 4,0 |
| 8 000 | 2 957 ms | 3,9 |

Cada duplicación multiplica por cuatro: cuadrático. Con 3 000 elementos tarda lo mismo con
la entrada aleatoria, ordenada o invertida (390–427 ms), que es lo que no haría un
algoritmo que se adapta. Y los números cierran: 3 000·2 999/2 = 4 498 500 llamadas × ~87 ns
por llamada = ~390 ms. El orden natural (`$^+`, `$^-`) usa `sort_by` y no se ve afectado
(8 000 elementos en 3 ms).

**La causa**, leída en el código: `crates/zymbol-vm/src/lib.rs` (instrucción `ArraySort`) y
`crates/zymbol-interpreter/src/collection_ops.rs` (`eval_collection_sort`) llevan **cada uno su
propia burbuja**, con un `for i / for j` fijo y sin la bandera «no hubo intercambios». La regla
del comparador es `keep(a, b) == true` deja `a` delante de `b`; falso los intercambia. El
comentario del intérprete dice «stable», y lo es solo con un comparador `<=` (con `<`, los
iguales responden `false` y se intercambian en cada pasada).

**El arreglo probado** es un único módulo, `zymbol-common/src/sort.rs`
(`merge_sort_by_keep`): mezcla ascendente por índices, **una llamada por comparación**,
`O(n log n)`, sin clonar elementos, con la misma regla de `keep` y propagando el primer error
del comparador tal cual. Los dos motores lo usan, así que no pueden volver a divergir. Los
mensajes de error (`sort comparator must return a Bool, got …`, GLB-024) se conservan.

| n | motor | antes | ahora | mejora |
|---|---|---:|---:|---:|
| 1 000 | `zyvm` | 74 ms | 4 ms | 19× |
| 3 000 | `zyvm` | 639 ms | 9 ms | 72× |
| 8 000 | `zyvm` | 4 412 ms | 18 ms | 247× |
| 20 000 | `zyvm` | 27 828 ms | 44 ms | 626× |
| 8 000 | `zytw` | 16 073 ms | 57 ms | 284× |

(Misma compilación antes y después, opt-level 1; salidas idénticas en todos los casos.)
Con 6 000 elementos, el caso nuevo `34_sort_custom_large` pasa de 2,5 s a 16 ms en la VM y de
9,6 s a 47 ms en el directo.

**Qué lo verifica**

- Cinco pruebas unitarias en `sort.rs` con la burbuja original como oráculo: mismo resultado
  con un orden total, estable con `<=`, descendente, todo igual, llamadas ≤ n·⌈log₂ n⌉, y el
  primer error corta la ordenación.
- El corpus de ZyQuality completo, 666 programas × 2 motores: 1 331 ejecuciones idénticas de
  1 332; la restante imprime `fecha::timestamp()`. Los dos programas que usan comparador propio
  (`22_sort_custom`, `32_destructure_extended`) coinciden con su `.expected`.
- Dos casos nuevos para el corpus, con salida de un oráculo en Python:
  `33_sort_custom_stable` y `34_sort_custom_large`.

**Una decisión de diseño que cambia de verdad.** Con un comparador **estricto** (`p[1] < q[1]`)
el orden entre elementos *iguales* es otro que antes: en 60 programas aleatorios de registros
`[clave, orden]` con empates, 100 de 120 ejecuciones difieren (con `<=`: 0 de 120, y siempre
estable). No es una regresión —el orden de antes entre iguales era un efecto de la burbuja—,
pero es observable. Dos salidas, ninguna decidida:

1. **Documentarlo:** «con `<` el orden entre iguales no está especificado; usa `<=` para que sea
   estable». Es lo que hace el parche tal como está (una llamada por comparación).
2. **Hacerlo estable para ambos:** cuando `keep(l, r)` es falso, preguntar también `keep(r, l)`;
   si es falso otra vez, son iguales y se toma `l`. Hasta ~1,5× llamadas, sigue siendo
   `O(n log n)`, y `<` y `<=` dan lo mismo. **No implementado ni medido.**

**Qué se desconoce:** `zyjs` (¿tiene su propia ordenación con comparador?) **no se miró**; ZyDDT
tampoco se corrió con el cambio. Solo dos programas del corpus y ninguna aplicación usan
comparador propio, así que el efecto del cambio de empates en aplicaciones reales (Go,
Chaturanga) no está medido.

**Estado.** **PROPUESTO** 2026-10-04: `ordenar_comparador.patch` (+199 −50, de ellas 154 son el
módulo nuevo con sus tests), aplica limpio sobre `820a60a`. Se queda en BUG y no en IDEA porque
tiene una causa localizada y un arreglo; la salida no es incorrecta, el coste sí.

---

## ERROR

### ERROR-BEN-004

**El manual dice que la VM es «~1.1–1.5× más rápida que Python en la mayoría de las cargas».
Con los programas de `bench/` es cierto para los bucles de enteros y falso para el resto.**

`MANUAL.md`, línea 121: «**VM**: production, ~1.1–1.5× faster than Python for most workloads».
La cifra es verdad a medias, y el propio autor la había señalado así antes de que este log la
midiera. Con la VM publicada v0.0.9, razón *tiempo de la VM / tiempo de Python* (menos de 1 es
ganar), sobre las pruebas cuyo tiempo supera los 10 ms en alguna compilación:

| tipo de carga | pruebas | VM / Python |
|---|---:|---|
| bucles y aritmética de enteros (`N2`, `N4`, `N5`, `ackermann`) | 4 | **0,68 – 0,94** (gana) |
| llamadas y funciones de orden superior (`fib`, `H1`–`H5`, `H9`) | 7 | 1,70 – 3,00 (pierde) |
| `??` (match por valor, rango y anidado) | 3 | 1,83 – 2,33 (pierde) |
| texto (strings, strings_modify, strings_stress, bench_text) | 14 | mediana 3,00 (pierde en las 14) |

La tabla fila a fila está en [IDEA-BEN-003](#idea-ben-003). La cifra
del manual coincide con la primera fila (y mejor); no con las otras tres. **No se sabe con qué
cargas ni con qué versión de Python se midió el 1,1–1,5×:** en Python 3.11 se abarataron las
llamadas entre funciones, y esta medición usa 3.12.

**Qué sujetaría una redacción exacta.** La tabla de arriba, regenerada con
`bench_vs_python/measure.py` en la máquina que fija la línea base.

**Decisión que es del autor:** si la frase se califica («más rápida que Python en bucles de
enteros; entre 1,7 y 3 veces más lenta en llamadas, funciones de orden superior y texto») o se
retira hasta tener una medición propia reproducible. Este log **no propone el texto**.

**Estado.** **ABIERTO.**

---

## IDEA

### IDEA-BEN-002

**Preparar y soltar el marco de registros era ~40 % de cada llamada en la VM. Cuatro cambios
pequeños en `zymbol-vm` lo recortan un 19–27 % en instrucciones. Es parte de `ZYVM-010`, con un
dato que esa ficha dejaba sin separar.**

Perfilado el **2026-10-04** con callgrind (instrucciones, determinista; `prof/perfilar.sh`) sobre
una compilación de `820a60a` con símbolos. `fib(22)` en la VM: 56 905 142 instrucciones,
~1 000 por llamada. El marco de `fib` tiene 7 registros (el compilador asigna 8 y descarta 1;
9 instrucciones por llamada):

| función | % antes | qué es |
|---|---:|---|
| `VM::exec` | 47 % | despacho |
| `Vec::resize` | **23 %** (13,0 M) | rellenar los registros del marco con `Unit` |
| `drop_in_place<Value>` + `Vec::truncate` | **19 %** (10,8 M) | soltar el marco al volver |
| `get_chunk` y el resto | 11 % | |

`resize` cuesta ~32 instrucciones por registro porque `resize(n, Value::Unit)` **clona** el valor
en cada hueco y, al no expandirse en línea, recorre entero el `match` de `Value::clone`.

**Qué cambia** (+66 −24, solo `zymbol-vm/src/lib.rs`):

1. `resize(n, Value::Unit)` → `resize_with(n, || Value::Unit)` (5 sitios).
2. `truncate(n)` → `truncate_regs`, que mira la etiqueta en línea y solo suelta (`drop_in_place`)
   lo que posee memoria (`String`, `Array`, `Tuple`, `NamedTuple`, `Closure`, `Error`); `Int`,
   `Float`, `Bool`, `Char`, `Unit` y `Function` no tienen nada que soltar (7 sitios). **Es el único
   `unsafe`**: baja el largo antes de soltar, como `Vec::truncate`, y cada hueco se suelta una vez.
3. `call_callable(…, args: Vec<Value>)` → `args: [Value; N]` (7 llamadores): `$>`, `$|`, `$<` y
   `$^` reservaban un `Vec` en el montón por cada llamada a la lambda.
4. `StoreGlobal` hacía `destroyed_globals.remove(..)` (un hash) en **cada** asignación a una
   global; ahora solo si el conjunto no está vacío. `get_chunk` en línea.

| programa | antes | ahora | menos |
|---|---:|---:|---:|
| `fib(22)` recursivo | 56 905 142 | 41 542 831 | **27 %** |
| `reduce` con lambda (50 000 llamadas) | 64 213 307 | 47 674 359 | **26 %** |
| bucle `(i*i) % 1000`, 200 000 vueltas | 246 263 919 | 198 660 592 | **19 %** |

En reloj (opt-level 1, VM, mediana de 3): `fib(30)` 213 → 129 ms, `ackermann` 18 → 12, `N2` 21 → 14,
`N4` 19 → 13, `N5` 194 → 134, `H3` 62 → 58; mejora mediana **1,13×** sobre las 16 pruebas de
≥ 10 ms. La VM de esta compilación pasa de ganar a Python en 2 a ganar en 4 (ver BEN-003).

**Relación con lo ya escrito.** `IDEA-GOL-007` (`ZyGoL/HALLAZGOS.md`) midió el coste de una llamada por
celda y lo localizó en soltar valores; `ZYVM-010` (`ZyDDT/HALLAZGOS/zyvm.md`, estado «abierto —
propuesta, no decisión») propone dos arreglos independientes. Este hallazgo aplica **la mitad del
primero** —no soltar lo que no posee nada— solo en el desmontaje del marco, y:

- **no toca** la escritura de un registro (`wreg!` / `reg_set`, donde `ZYVM-010` pone ~11 % de todo
  programa) ni la reutilización de temporales en el compilador (`alloc_temp`, que hace el marco de
  `vecinos` de 34 registros): **esas dos partes siguen abiertas;**
- **aporta el dato que `ZYVM-010` dejaba «sin separar»** (qué parte de lo que se suelta no posee
  nada): en `fib` los 7 registros del marco contienen enteros o `Unit` al volver, es decir, **todo
  el desmontaje es de valores que no poseen nada**. En un programa que devuelva filas del tablero
  no tiene por qué serlo; eso no se midió.

**Qué lo verifica:** el corpus completo, 665 programas × 2 motores, **1 330 ejecuciones idénticas**
a las de la versión que solo tenía el cambio del orden (se excluye `i18n/test_http_api.zy`, que
pide a `httpbin.org` y cambia entre ejecuciones del mismo binario); `cargo test -p zymbol-vm`, 11 de 11.
Los doctests **no se pudieron correr**: el entorno de la medición no tiene `rustdoc` en el PATH.

**Lo que no se ha hecho:** `exec` sigue siendo el 63–70 % en bucles y recursión (~30 instrucciones
nativas por instrucción de la VM) y no se miró; `call_callable` y la **reentrada a `exec` por cada
elemento** son ahora el 27 % + 25 % de un `reduce`: quitarla (ejecutar el cuerpo de `$>`/`$<` como un
bucle de la VM) es un cambio mayor y no está hecho; no se perfilaron `??` ni el texto.

**Estado.** **PROPUESTO** 2026-10-07 (perfil del 2026-10-04): `vm_llamadas.patch` (+66 −24), a aplicar **después** de
`ordenar_comparador.patch`. Se queda en IDEA —como `IDEA-GOL-007`— porque lo accionable es un
objetivo de optimización de la VM, no un defecto.

### IDEA-BEN-003

**La VM gana a Python en 4 de 16 pruebas generales y en 0 de 14 de texto. El intérprete directo
es entre 12 y 14 veces más lento que Python (mediana).**

Medido entre el **2026-10-04** (primeros ports) y el **2026-10-07** (compilación final): ports a Python de **9 de los 12** programas de `zyquality/bench/`
(`bench_recursion`, `bench_collections`, `bench_match`, `stress_v2/bench_numeric`,
`stress_v2/bench_hof`, y los cuatro de texto: `bench_strings`, `bench_strings_modify`,
`bench_strings_stress`, `stress_v2/bench_text`): 65 mediciones, **y el resultado coincide con el de
Zymbol en las 65** —eso, además, confirma que se leyeron bien `$~~[…]`, `$??`, `$+[n]`, `$-[a..b]`
y `$[a..b]`—. Python 3.12. 30 de las 65 superan los 10 ms; esas son las de la tabla.

Cada celda es ms; *pub.* es la VM publicada v0.0.9 (opt-level 3); *ahora* es la rama v0.0.10 con los
parches de BEN-001 y BEN-002 (opt-level 1).

| prueba | Python | VM pub. | directo pub. | VM ahora | ahora / Python |
|---|---:|---:|---:|---:|---:|
| recursion: fib(30) | 90 | 189 | 1 879 | 129 | 1,43 |
| recursion: ackermann(3,6) | 16 | 14 | 228 | 12 | **0,75** |
| numeric: N2 suma de dígitos | 31 | 21 | 96 | 14 | **0,45** |
| numeric: N4 cuadrados módulo | 22 | 18 | 34 | 13 | **0,59** |
| numeric: N5 fizzbuzz 1M | 193 | 181 | 1 140 | 134 | **0,69** |
| match: por valor / por rango | 6 / 6 | 14 / 11 | 84 / 84 | 12 / 12 | 2,00 / 2,00 |
| hof: H1 map / H3 reduce | 10 / 23 | 17 / 40 | 135 / 408 | 21 / 58 | 2,10 / 2,52 |
| hof: H2 filter / H4 filter+reduce | 9 / 7 | 22 / 16 | 142 / 112 | 23 / 18 | 2,56 / 2,57 |
| hof: **H8 orden con comparador** | **< 0,5** | **38** | **300** | **3** | cota |
| texto: S1 concatenación (8 000) | 1 | **34** | **132** | **3** | cota |
| texto: T1 plantilla / S6 plantilla con números | 2 / 2 | 6 / 7 | 14 / 17 | 3 / 4 | 1,5 / 2,0 |
| texto: T2 unir / S9 unir | 1 / 1 | 4 / 3 | 19 / 12 | 3 / 2 | 3,0 / 2,0 |

Lo que dicen los números, por separado:

1. **Gana la aritmética de bucles, pierde todo lo que llama.** Con la VM publicada: general, gana en
   4 de 16, mediana VM/Python **1,79**; texto, **0 de 14**, mediana **3,00**; el intérprete directo,
   mediana **14,3** y **12,0**. (Con la compilación *ahora*, a pesar de opt-level 1: general también
   4 de 16, mediana 2,00; texto 0 de 14, mediana 2,00.)
2. **El coste de una llamada o de una lambda es ~2×**: unos 70–115 ns en Zymbol contra 33–47 ns en
   Python, que cierra con el 2,0–2,6× de `H1`–`H5` y con `IDEA-GOL-007`.
3. **`S1` mejoró 11× entre versiones y no es por BEN-001 ni BEN-002.** La concatenación repetida pasa de
   34 a 3 ms en la VM y de 132 a 10 ms en el directo entre la v0.0.9 y la rama v0.0.10. Algo ya cambió
   en cadenas; no se miró qué.
4. **El directo de v0.0.10 es más rápido que el publicado en las funciones de orden superior**
   (`H1` 135 → 93 ms) a pesar de compilarse con menos optimización. No se puede separar si es código
   o es perfil.

**Límites.** Una máquina; Python 3.12; **9 de 12 programas** (faltan `bench_index_read`, `stress`,
`bench_pipeline`, `bench_recursion_loop`); los ports a Python usan `append` donde Zymbol hace
`a = a$+ x`, que es lo idiomático en cada uno pero no es el mismo coste; las razones contra un Python
que marca 0–1 ms son cotas. El resto de cifras, contra *esta* VM compilada con opt-level 1, **no
sustituyen** a una medición con el perfil release del repositorio.

**Qué lo reproduce:** `bench_vs_python/` (ports + `measure.py`; `LEEME.md` dice cómo).

**Estado.** **MEDIDO** 2026-10-04 a 2026-10-07. No cambia código; alimenta BEN-002 y BEN-004.

---

## Qué costó, y qué dice

Cuatro hallazgos que ninguna aplicación habría dado: nacieron de **comparar el lenguaje contra otro con
los mismos programas**, no de usarlo. Un BUG con arreglo (BEN-001), una IDEA con parche (BEN-002), una
medición (BEN-003) y una afirmación del manual que no se sostiene (BEN-004).

Lo que se equivocó por el camino, apuntado porque forma parte del método:

- **Un valor atípico se tomó por un dato.** La primera medición de `fib(27)` en la VM dio 1,0 s; repetida
  da 47–58 ms. De ahí salió una conclusión («queda margen enorme en la VM») que había que retirar.
  *Una medición no es un dato hasta que se repite.*
- **Una prueba vacía dio «idéntico».** La comparación de empates entre la burbuja y la mezcla salió igual
  en todo… porque los dos binarios fallaban igual con una sintaxis de registro inexistente (`(k: 1)` en
  lugar de `#(k: 1)`) y no imprimían nada. Se detectó porque la salida estaba vacía. *Una prueba que no
  puede fallar no prueba.*

Lo que sí funcionó, y vale para el siguiente log: **instrucciones en vez de milisegundos** (callgrind)
para comparar dos binarios sin el ruido del reloj; **la comparación diferencial** entre el binario de antes
y el de después sobre todo el corpus (lo que dio el 100 de 120 de BEN-001 y los 1 330 idénticos de BEN-002);
y **un oráculo independiente** (`sorted()` de Python, que es estable) para la ordenación.

---

## Ficheros

| fichero | qué es |
|---|---|
| `ordenar_comparador.patch` | BEN-001 (sobre `820a60a`) |
| `vm_llamadas.patch` | BEN-002 (sobre el anterior) |
| `NOTAS_orden_comparador.md`, `NOTAS_optimizaciones_vm.md` | las notas largas de cada parche |
| `corpus/33_sort_custom_stable.*`, `corpus/34_sort_custom_large.*` | dos casos nuevos para ZyQuality |
| `prof/perfilar.sh`, `prof/*.zy` | cómo se perfiló |
| `bench_vs_python/` | ports a Python y `bench_vs_python/measure.py` |
