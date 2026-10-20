# Hallazgos de rendimiento — Zymbol **v0.0.10**

Encontrados con un barrido por **curva de crecimiento** (`scaling.py`, en `ZyBigBench.zip`): se
mide cuánto tarda cada operación con n, 2n, 4n y 8n y se estima el exponente `b` de
`tiempo ~ n^b`. Después, `gap.py` repite las operaciones con un gemelo en Python que sirve de
oráculo de valores y de referencia de tiempo (sección «Brecha frente a Python»). `b ≈ 1` es lineal; `b ≈ 2`, cuadrático. Una operación que cuesta
O(n) por llamada convierte un bucle de n vueltas en uno cuadrático, aunque cada vuelta parezca
barata.

Fecha: 2026-10-10. Binarios: `zymbol 0.0.10` en `c309d44` (nuevo) y `38b21bf` (anterior), ambos
compilados **sin LTO**, en un contenedor de 4 GB con Python 3.12.3. «Verificado» significa que
lo reproduje con un programa mínimo en esta sesión; «Hipótesis», que lo infiero y no lo probé.

> **Estado en la versión publicada (2026-10-11):** la etiqueta `v0.0.10` apunta a `d736ae6`, que
> corrige **PERF-01, PERF-02 y la parte de actualización de PERF-03**, hace lineal `s = s "x"` en
> el árbol y alinea mi DG-09. Siguen abiertos PERF-03 (búsqueda lineal), 04, 05, 06 (en la VM) y
> 07. Hay un hallazgo nuevo, PERF-08. Ver «Estado en la versión publicada» más abajo.
>
> **Ninguno de los siete es una regresión:** el binario anterior se comporta igual en todos.
> Tres (PERF-01, 02 y 04) son **de la VM**: el tree-walker hace lo mismo en tiempo lineal.
> Esa asimetría es la pista más útil, porque el árbol ya contiene el camino rápido.

## Estado en la rama `v0.0.11` (revisado el 2026-10-19)

> **Esta sección manda sobre el resto del documento.** Lo que sigue debajo es el informe tal como se escribió entre
> el 2026-10-10 y el 2026-10-11, contra la v0.0.10, y se deja intacto como registro de lo que se midió. Ahí PERF-03 a
> 07 figuran como abiertos, y en la rama ya no lo están. El estado vivo de cada ficha lo calcula `./bin/zyddt findings`
> en `ZyDDT/`, y las razones las sujeta `zyquality/cost/` en cada `zyq suite`.

Revisado sobre `7ef269c` (`interpreter/`), con `zyq suite --only cost` en verde y una sonda por cada «Falta probar»
de abajo.

| ID | Estado | Ficha | Qué lo sujeta |
|----|--------|-------|---------------|
| PERF-01 `v[i]$~ x` | **Corregido** (2026-10-10) | `ZYVM-013` | `cost` `growth/update-local`, `update-module-state` |
| PERF-02 `$-[idx]` | **Corregido** (2026-10-10) | `ZYVM-013` | el mismo mecanismo (`$-[1]` por el principio: ver «Falta probar», abajo) |
| PERF-03 diccionario | **Corregido** en los tres motores (2026-10-16): `IndexMap`, y desde el 2026-10-18 hash foldhash | `GLB-131`, `GLB-132` | `growth/dictionary-by-key` |
| PERF-04 `@ ch:texto` | **Corregido** (2026-10-16): un cursor de bytes, `StrCharNext` | `ZYVM-024`, `ZYVM-025` | `growth/foreach-over-text`, `corpus/loops/14_foreach_string_snapshot.zy` |
| PERF-05 a, el corte | **Corregido** en la VM y el tree-walker (2026-10-16): copia sólo el trozo | `GLB-130`, `ZYVM-026` | `growth/slice-a-text` (por `bytes`) |
| PERF-05 b, `s$#` y `s[i]` | **Corregido en la VM** (2026-10-17): el texto guarda su número de caracteres. **Queda** la posición en un texto no ASCII | `ZYVM-028` · `GLB-139` (abierto) · `ZYTW-016` (abierto) | `growth/read-a-text` (desde hoy también por reloj en la VM), `growth/index-a-text` |
| PERF-06 `s = s "x"` | **Corregido** en la VM (2026-10-16); el árbol ya lo estaba en `d736ae6` | `ZYVM-023` | `growth/concat-local`, `concat-in-function`, `concat-module-state` |
| PERF-07 recursión | **Corregido** (2026-10-16): `##Depth`, capturable con `!?`, a 10 000 llamadas activas, igual en los tres motores; pila de 512 MiB | `GLB-133`, `ZYTW-017`, `ZYVM-027` | `corpus/errors/runtime/depth_*.zy` |
| PERF-08 musl | **Corregido** (2026-10-19): `mimalloc` sólo en el estático, con tres opciones para que no retenga memoria. Del ×2,1 que quedaba en el `HEAD` (×17 en la v0.0.10) a como glibc; ×0,983 en los 16 programas | `GLB-134` | la medición de la ficha, que hay que repetir en la release: la puerta no construye el estático |

### Lo que esta revisión encontró

Tres hallazgos nuevos, archivados con su caso en `zyquality/cost/` como deuda declarada (`open_finding`). Lo que se
hace con cada uno está en el «Plan de cierre» de `interpreter/ROADMAP_V0011_ES.md`:

| Ficha | Qué | Motores | Medido |
|---|---|---|---|
| `GLB-139` | `s[i]` y un corte buscan su posición recorriendo el texto. Es el resto de PERF-05 b. **Corregido en la VM el 2026-10-19** (una miga cada 64 caracteres: 128 000 «ñ», 941 → 39 ms); deuda de la v0.0.11 en el árbol y zyjs | VM y árbol con texto no ASCII; zyjs con cualquiera | VM ×13 de 32 000 a 128 000 «ñ»; ASCII plano |
| `GLB-140` | `m[i>j]$~ v` copia el array exterior entero en cada edición. **Corregido el 2026-10-19** en el árbol y zyjs | árbol y zyjs; la VM edita en el sitio | árbol: `copied` = filas + 3 por edición; ahora 0 |
| `ZYJS-068` | `m$+ [0, 0, 0]`: con un literal de colección como operando, zyjs copia el receptor. **Corregido el 2026-10-19** | zyjs | ×21 de 8 000 a 32 000; ahora ×1,8 |

### Los «Falta probar» de abajo, contestados

- **`$+` de arreglos de arreglos:** lineal en los dos motores de Rust, con `copied = 0` en las cinco formas probadas.
  En zyjs, cuadrático con un literal (`ZYJS-068`).
- **`$-` por el principio:** sin copia (`copied = 0`, bytes lineales), pero cada `$-[1]` desplaza los elementos
  que quedan, así que n de ellos cuestan n² en cualquier lenguaje: Python `pop(0)` 6 → 22 → 87 ms con 10 000, 20 000
  y 40 000. La VM, 21 → 67 → 189 ms (~×2,2 de Python). El árbol, 100 → 418 → 3 141 ms (~×36): su `Value` mide
  **120 bytes** contra los 16 de la VM, mueve 7,5 veces más memoria y se sale de la caché antes. No es un defecto de
  algoritmo sino el tamaño del valor del árbol, que pesa igual en la memoria de cualquier colección suya. **Corregido
  el 2026-10-19** (`ZYTW-019`): el valor mide 24 bytes, y el árbol tarda ~313 ms donde tardaba ~2 640.
- **Cadenas muy largas no ASCII:** recorrerlas con `@ ch:s` es lineal en los dos motores. Indexarlas no lo es
  (`GLB-139`).
- **`$~` profundo (`m[i>j]$~ x`):** constante en la VM; O(filas) por edición en el árbol y en zyjs (`GLB-140`).
- **`s[i]`** (PERF-05, «Qué falta»): ver `GLB-139`.
- **Por qué `s = s "x"` era cuadrático en la VM:** el compilador mandaba `ConcatStr` a un temporal y la rama que
  reutiliza el búfer exigía el mismo registro (`ZYVM-023`).

---

## Resumen

| ID | Operación | Qué pasa | Motores | Gravedad |
|----|-----------|----------|---------|----------|
| [PERF-01](#perf-01) | `v[i]$~ x` | Cuesta O(longitud del arreglo) por asignación | **solo VM** | Alta |
| [PERF-02](#perf-02) | `v = v $-[idx]` | Quitar el último elemento cuesta O(longitud) | **solo VM** | Alta |
| [PERF-03](#perf-03) | `d[k]` | Buscar una clave cuesta O(posición de la clave); insertar n claves es cuadrático | VM y árbol | Alta |
| [PERF-04](#perf-04) | `@ ch:texto` | Recorrer un texto cuesta O(longitud) **por carácter** | **solo VM** | Alta |
| [PERF-05](#perf-05) | `s$#`, `s$[a..b]` | Cuestan O(longitud del texto) por llamada, incluso un prefijo de 10 caracteres | VM y árbol | Media |
| [PERF-06](#perf-06) | `s = s "x"` | Acumular texto es cuadrático | VM y árbol | Media |
| [PERF-07](#perf-07) | recursión profunda | El árbol aborta con *stack overflow* en ~10 000 niveles | **solo árbol** | Media |

---

## Estado en la versión publicada (v0.0.10, 2026-10-11)

**Qué se midió.** La página `zymbol-lang.org/install.html` publica la `v0.0.10`; su etiqueta
apunta al commit **`d736ae6`**, el mismo que yo había compilado (13 commits después de
`c309d44`, donde se midieron los siete hallazgos). Descargué dos binarios oficiales y verifiqué
su SHA256 contra el prefijo de la página: el estático para Linux x86_64 (musl, `f17f98542dbb…`)
y el `.deb` x86_64 (glibc, `965a4b57b7a6…`). Ambos dan `zymbol 0.0.10`. Los 52 valores de
`gap.py` coinciden con Python con el estático; con el `.deb`, los 16 programas completos, y
ZyBF pasa 13 de 13 en los dos motores.

| ID | Estado en `d736ae6` | Evidencia |
|----|---------------------|-----------|
| PERF-01 `v[i]$~ x` (VM) | **Corregido** | `arr_update_each`, n = 16 000: **1 073 → 3 ms**; `b` de 1,98 a **0,98** (n = 1 600 000 en 259 ms). `arr_update_one`: 907 → menos de 1 ms |
| PERF-02 `$-[idx]` (VM) | **Corregido** | 555 → 1–2 ms; `b` de 1,99 a **1,04** |
| PERF-03 diccionarios | **Mejorado, abierto** | Actualizar la primera clave: 229 → menos de 1 ms. Insertar 8 000 claves: 2 148 → 83–88 ms (×24), pero `b = 1,95` en la VM y `2,30` en el árbol hasta 64 000 claves (5,5 s y 8,6 s): la búsqueda sigue siendo lineal |
| PERF-04 `@ ch:texto` (VM) | Abierto | 147 456 → 294 912 caracteres: 351 → 1 471 ms (×4,2); `b = 1,97` |
| PERF-05 `s$#`, `s$[a..b]` | Abierto | Con 147 456 caracteres: `s$#` ×20 000 en 46–47 ms; `s$[1..10]` ×2 000 en 338 ms (`.deb`) y 639 ms (estático) |
| PERF-06 `s = s "x"` | **Corregido en el árbol, abierto en la VM** | Árbol: `b` de 2,22 a **1,03** (2 000 000 de caracteres en 321 ms). VM: `b = 2,11`, 128 000 añadidos en 332–338 ms con glibc y 3 731 ms con el estático (Python: 2–5 ms) |
| PERF-07 recursión en el árbol | Abierto, y el límite **bajó** | Ver abajo |
| DG-09 (mío) `f = f + "."` | **Corregido** | El árbol y la VM rechazan por igual `f = f + "."` y `f += "."` |

**PERF-07: el límite depende de la compilación.** Búsqueda binaria del primer nivel que aborta
con `stack overflow`: ~9 900 con mi compilación sin LTO de `d736ae6` y ~10 000 con la de
`c309d44`, pero **~8 400 con los dos binarios oficiales** (el `.deb` y el estático). Es un
tamaño de pila fijo y marcos de distinto tamaño según la compilación; el aborto sigue sin error
de Zymbol (código 134).

### PERF-08 (nuevo): el binario estático con musl es entre 1,6 y 11 veces más lento que el `.deb`

Mismo commit, VM, tamaño grande de `gap.py`, ms:

| Operación | `.deb` (glibc) | estático (musl) | estático / `.deb` |
|---|---:|---:|---:|
| `str_concat` (128 000 añadidos) | 332 | 3 731 | **11,2** |
| `str_interp` (1 000 000) | 161 | 376 | 2,3 |
| `str_slice_small` (147 456) | 338 | 639 | 1,9 |
| `print_lines` (200 000) | 183 | 311 | 1,7 |
| `closure_create_call` (1 000 000) | 196 | 310 | 1,6 |

Las demás operaciones medidas (`arr_append`, `map_filter_reduce`, `sort_comparator`,
`call_overhead`, `match_range`) son iguales o casi, y `str_iter` y `str_len` son iguales
en los dos. La página anuncia el estático como «Any Linux» y es el que se descarga por
defecto.

- **Causa (CONFIRMADA con una prueba independiente en C):** el asignador de memoria de musl.
  Ver «Causas confirmadas».
- **Sobre LTO:** el `.deb` oficial (que sí se compila con LTO) y mi compilación sin LTO del mismo
  commit dan cifras casi iguales (`call_overhead` 127 y 126 ms, `map_filter_reduce` 217 y 224,
  `sort_comparator` 240 y 220), salvo `str_iter` y `str_len`, que van un 28–30 % mejor en el
  oficial. **La sospecha que dejé en el informe anterior, que mi compilación subestimaba a
  Zymbol, no se sostiene en general.**

### Programas completos con el `.deb` oficial (`run.py`, cinco ejecuciones)

- **16 de 16 salidas coinciden con Python.**
- Frente a Python, en los 13 programas con 50 ms o más en Python: media geométrica
  **0,84** (mediana 0,96); antes era 1,04. **Gana en 7:** `mandelbrot` 0,39, `collatz` 0,44,
  `primes_trial` 0,46, `sort_builtin` 0,47, `loop_mod` 0,53, `matmul` 0,68, `match_loop` 0,96.
  **Pierde en 6:** `hof_chain` 1,16, `fib_rec` 1,22, `nqueens` 1,27, `sort_cmp_300k` 1,28,
  `tak` 1,89, `strings_scan_short` 1,99. `strings_scan_long` queda en 21 veces (PERF-04), pero
  Python lo hace en 31 ms y no entra en la media.
- Frente a la compilación anterior (`c309d44` sin LTO), en 13 programas: media geométrica
  **0,81**, de 0,59 a 1,04. Esa cifra mezcla el cambio de commits con el cambio de compilación
  (LTO y glibc).

---

## Causas confirmadas (código y pruebas)

Todo sobre `d736ae6`. «Confirmada» significa que el código, el mensaje de un commit del autor o
una prueba independiente muestra el mecanismo; entre paréntesis, dónde.

| ID | Causa | Evidencia |
|----|-------|-----------|
| PERF-01, 02 | Una copia de registro (`CopyReg`) antes de `DeepSet` deja un **segundo dueño** del `Rc`, y `Rc::make_mut` clona la colección entera | Mensaje del commit `ee48143`: «`CopyReg` before `DeepSet` made a second owner of the `Rc`»; afectaba también a `t$-[i]`, `t$+ v` y al estado de módulo. Mi hipótesis era esa, pero el commit la confirma y la amplía |
| PERF-03 | Un diccionario es `Value::NamedTuple(Vec<(String, Value)>)`; leer es `fields.iter().find(|(k, _)| *k == key)` y escribir es `rc.iter().position(...)`, una **búsqueda lineal**. Además la lectura copia la clave a un `String` nuevo | `zymbol-vm/src/lib.rs` ~2463 y ~5269. Ya hay un `indexmap` como dependencia en `zymbol-common` |
| PERF-04 | `@ ch:texto` se compila a un `StrLen` más un `StrCharAt` por vuelta; `StrCharAt` llama a **`s.is_ascii()`** (recorre todo el texto) y, si hay un carácter no ASCII, a `chars().nth(i)` (O(i)). El comentario del código lo llama «O(1) ASCII fast path», pero `is_ascii()` es O(longitud) | `zymbol-compiler/src/lib.rs` ~4921; `zymbol-vm/src/lib.rs` ~3283 |
| PERF-05 | `s$#` es `if s.is_ascii() { s.len() } else { s.chars().count() }`; el índice `s[i]` hace `chars().count()` y `chars().nth(i)`; el trozo `s$[a..b]` hace `chars().count()` y `char_indices().nth(p)` | `zymbol-vm/src/lib.rs` ~2146, ~2526, ~3394 |
| PERF-07 | El programa corre en un hilo con una **pila fija de 64 MiB** (`PROGRAM_STACK`); no hay tope de profundidad propio. El comentario del autor lo describe: al agotarla «the next one aborted the process with no Zymbol error at all» | `zymbol-cli/src/main.rs` ~181–186. 64 MiB entre ~8 400 niveles son unos 8 KB por marco del árbol |
| PERF-08 | El asignador de musl | Prueba en C abajo; no hay `global_allocator` en el repositorio y el estático se construye con `x86_64-unknown-linux-musl` y `+crt-static` (`packaging/build-packages.sh`) |

**Coherencia numérica de PERF-04 y 05.** Con 589 824 caracteres, una vuelta de `@ ch:texto`
cuesta 14,6 µs: son ~40 GB/s, la velocidad típica de `is_ascii()`. `s$#` sobre 294 912
caracteres cuesta 7 µs por llamada: ~42 GB/s. Cuadra con que sea esa llamada y no otra cosa.

**Una predicción del código que sí comprobé.** Como con texto no ASCII se usa
`chars().nth(i)`, un texto con una sola `é` por cada 72 caracteres debía ser más lento en
la VM y no en el árbol. Recorrerlo (`confirmaciones/`, `iter_ascii.zy` e `iter_uni.zy`):

| caracteres | VM ASCII | VM con `é` | árbol ASCII | árbol con `é` |
|---:|---:|---:|---:|---:|
| 18 432 | 5 ms | 19 ms | 4 ms | 4 ms |
| 36 864 | 32 ms | 90 ms | 16 ms | 9 ms |
| 73 728 | 88 ms | 193 ms | 22 ms | 16 ms |

**Prueba independiente de PERF-08 (C, mismo patrón que `s = s "x"`).** Un programa en C que
reserva `len+1`, copia y libera 128 000 veces, compilado una vez con glibc y otra con
`musl-gcc -static` (tres pasadas cada uno):

| patrón | glibc | musl |
|---|---:|---:|
| copiar y liberar un texto creciente hasta 128 000 bytes | **312–319 ms** | **3 504–3 588 ms** |
| `malloc`+`free` de 64 KB o más, por operación | 0,02–0,03 µs | 6,5–9,8 µs |
| `malloc`+`free` de 512 bytes a 16 KB, por operación | 0,01–0,02 µs | 0,14–0,23 µs |
| 4 000 000 de `malloc(48)` de vida corta | 43 ms | 157 ms |

El patrón reproduce la proporción de `str_concat` fuera de Zymbol: **11,2 veces** (Zymbol: 332
contra 3 731 ms), casi al milisegundo. Los bloques de 64 KB o más pasan de 0,02 µs a unos
8 µs en musl, y un texto de decenas de miles de caracteres cruza ese umbral enseguida.
Las demás diferencias (interpolación 2,3×, trozos 1,9×, cierres 1,6×) son del orden de la
penalización de objetos pequeños (3,7×), pero eso no lo comprobé operación por operación.
**Para arreglarlo** habría que enlazar el estático con otro asignador (por ejemplo `mimalloc`) o
recomendar el `.deb` o `.rpm`; no probé ninguna de las dos.

### PERF-07, dato nuevo: recursar a través de `$>`

Como dice el comentario de `PROGRAM_STACK`, en la VM una función que recursa a través de un
operador de orden superior vuelve a entrar en el bucle de despacho. Recursión
`f(m) = ([m] $> (x -> f(x - 1)))[1] + 1`, binario `.deb`: la VM aborta hacia los **2 800
niveles** (sin error hasta ~2 734, aborta desde ~2 832) y el árbol hacia los **6 400**; los dos
con código de salida 134. La recursión directa llega a ~8 400 en el árbol y a millones en la VM.

---

## PERF-01

**`v[i]$~ x` cuesta O(longitud del arreglo) en la VM. En el árbol es lineal en total.**

- **Reproducción mínima** (`confirmaciones/array_update_por_tamano.zy`): 5 000 actualizaciones de
  `v[1]` sobre un arreglo de m elementos.

  | m | VM | árbol |
  |---|---:|---:|
  | 1 000 | 37 ms | 9 ms |
  | 10 000 | 212 ms | 11 ms |
  | 100 000 | 1 989 ms | 33 ms |

- **Programa de n actualizaciones sobre n elementos** (`arr_update_each` del barrido): VM
  `b = 1,98`, con 17,9 s para n = 64 000; árbol `b = 1,01`, con 0,47 s para n = 1 024 000.
  A n = 40 000 la VM es unas 280 veces más lenta que el árbol.
- **Causa (CONFIRMADA, ver «Causas confirmadas»):** `compile_collection_update_as`
  (`zymbol-compiler/src/lib.rs`, ~4006) emite `CopyReg(dst, r_arr)` y luego `DeepSet(dst, …)`.
  La copia de registro deja **dos referencias** al mismo arreglo, y `Rc::make_mut` clona el
  `Vec` entero en cada asignación. La variante `DeepSetInPlace`, que saca el valor del registro
  con `mem::replace`, existe pero solo se emite para la forma `t[i] = val`.
- **Qué lo vuelve grave:** `v[i]$~ x` es la única forma de modificar un elemento. Cualquier
  tabla, criba, programación dinámica o cinta de Brainf\*\*\* sobre un arreglo grande paga
  O(n) por escritura. Explica, **sin que lo haya probado**, que ZyBF sea solo ~1,5× más rápido
  en la VM que en el árbol.
- **Qué lo sujetaría:** un caso de corpus que haga 5 000 asignaciones sobre un arreglo de
  100 000 y exija menos de, digamos, 50 ms.

## PERF-02

**`v = v $-[idx]` sobre el último índice cuesta O(longitud) en la VM; en el árbol es lineal.**

- `arr_remove_last` del barrido: quita n veces el último elemento. VM `b = 1,99` (n = 64 000:
  8,9 s); árbol `b = 0,98` (n = 1 024 000: 0,41 s); VM anterior `b = 2,05`.
- **Causa (CONFIRMADA):** la misma de PERF-01; el mensaje del commit que lo corrigió cita
  `t$-[i]` entre las operaciones afectadas.
- **Qué falta:** no probé quitar por el principio ni por el medio; ahí un coste lineal sería
  esperable en cualquier implementación.

## PERF-03

**Un diccionario se comporta como una lista de pares: buscar una clave cuesta O(posición de la
clave), y por eso insertar n claves es cuadrático. En los dos motores.**

- **Lectura según la posición de la clave** (20 000 lecturas, binario oficial `.deb`,
  `confirmaciones/dict_pos.zy`):

  | claves | primera clave | clave del medio | **última clave** |
  |---:|---:|---:|---:|
  | 1 000 | 1 ms | 25 ms | 9 ms |
  | 2 000 | 3 ms | 16 ms | 83 ms |
  | 4 000 | 2 ms | 73 ms | 195 ms |
  | 8 000 | 1 ms | 184 ms | **479 ms** |

  Leer la primera clave cuesta lo mismo con 1 000 que con 8 000; leer la última, 24 µs con
  8 000 claves (unos 3 ns por clave recorrida). El árbol da lo mismo.
- **Inserción** (`dict_insert`): al insertar hay que comprobar si la clave ya existe, y esa
  búsqueda es la lineal de arriba. `b = 2,04` (VM), `2,04` (árbol) y `1,97` (VM anterior) en la
  versión del 10 de octubre; con n = 16 000 claves, **9 a 12 s**.
- **Corrección de lo que afirmé antes.** En la primera versión de este informe dije que «la
  lectura sí es O(1)», y retiré una alarma de `dict_lookup` como «artefacto». La retirada era
  una conclusión equivocada: mi prueba leía siempre la clave `"k1"`, que **es la primera
  insertada**, justo la que una búsqueda lineal encuentra al instante. La lectura de la
  última clave sí delata el problema. (La alarma original con `b = 2,23` sí era ruido de
  medición, pero la causa que la explicaba estaba en otro sitio.)
- **Causa (CONFIRMADA en el código):** el diccionario se guarda como un `Vec` de pares y se busca
  por recorrido, no por tabla hash. Eso explica a la vez que leer la primera clave sea
  instantáneo, que insertar sea O(n) y que actualizar una clave existente cueste lo mismo que
  leerla (en `c309d44` costaba además una copia, ver el estado más abajo).
- **Frente a Python** (diccionario de 4 000 claves, última clave): Python no depende de la
  posición; Zymbol tarda ~24 µs por lectura con 8 000 claves.

## PERF-04

**Recorrer un texto con `@ ch:texto` cuesta O(longitud del texto) *por carácter* en la VM; el
árbol es lineal y rápido.**

- Una sola pasada, sin contar cómo se construyó el texto (`str_iter` del barrido):
  VM `b = 1,99` con **8,6 s para 589 824 caracteres** (14,6 µs por carácter); árbol, **36 ms
  para 1 179 648 caracteres**. Por carácter, la VM es del orden de 500 veces más lenta que el
  árbol; la VM anterior da lo mismo.
- Confirmación independiente (`confirmaciones/str_iter_por_tamano.zy`): con **880 000
  caracteres visitados**, textos de 22 000 caracteres tardan 450 ms y textos de 88 000 tardan
  1 729 ms en la VM; en el árbol, 113 y 165 ms.
- **Causa (CONFIRMADA en el código):** cada vuelta llama a `s.is_ascii()`, que recorre todo el
  texto. Con un texto no ASCII usa además `chars().nth(i)`.

## PERF-05

**`s$#` y `s$[a..b]` cuestan O(longitud del texto) por llamada, en los dos motores; un prefijo de
10 caracteres también.**

Con temporizador dentro del programa (`confirmaciones/str_t.zy`):

| caracteres | `s$#` ×5 000 | `s$[1..10]` ×2 000 | `s$[(n-10)..(n-1)]` ×2 000 |
|---:|---:|---:|---:|
| 18 432 | 3 ms | 33 ms | 35 ms |
| 73 728 | 9 ms | 128 ms | 126 ms |
| 294 912 | 35 ms | 637 ms | 548 ms |

(VM nueva. La VM anterior y el árbol dan cifras del mismo orden.) Un prefijo de 10 caracteres
sobre 295 000 cuesta ~0,3 ms, el mismo precio que un trozo del final.

- **Causa (CONFIRMADA en el código):** el texto se guarda en UTF-8 y la posición de carácter se
  resuelve contando desde el inicio; un `s$#` en la condición de un bucle lo vuelve cuadrático. Es un compromiso
  de diseño habitual, pero aquí no se documenta en ninguna parte que he leído.
- **Qué falta:** no probé `s[i]` (índice de carácter).

## PERF-06

**Acumular texto con `s = s "x"` es cuadrático en los dos motores.**

- `str_concat`: VM `b = 2,09` (n = 512 000 añadidos: 5,0 s); árbol `b = 2,22` (n = 256 000:
  8,9 s); VM anterior `b = 2,10`.
- **Frente a Python:** dentro de una función, CPython amplía el texto en su sitio y 128 000
  añadidos tardan **4,5 ms** (Zymbol: 352 ms, brecha 26 → 78 al doblar n). A nivel de módulo
  CPython **también** es cuadrático (340 ms con el mismo tamaño), de modo que mi primera
  comparación daba paridad y era un listón demasiado fácil.
- `$+` sobre arreglos no tiene este problema: 800 000 añadidos tardan 44 ms.

## PERF-07

**El tree-walker se cae con `fatal runtime error: stack overflow, aborting` hacia los 10 000
niveles de recursión, sin un error de Zymbol. La VM llega a millones.**

- `confirmaciones/recursion_profunda.zy`: la función `down(m)` que suma uno por nivel. Árbol:
  1 000 y 5 000 niveles bien; entre 9 921 y 10 000 el proceso aborta con código **134**
  (`SIGABRT`). Igual en la rama anterior. VM: 200 000 y 3 000 000 bien; con 30 000 000 el
  sistema mata el proceso (`Killed`; no determiné si fue por memoria).
- No hay forma de capturarlo desde Zymbol: el proceso entero desaparece, con la salida
  parcial que hubiera.
- **Qué falta:** si hay un límite deliberado o un tamaño de pila fijo en el hilo
  `zymbol-program`; no lo busqué.

---

## Brecha frente a Python (ZyGap)

**Planteamiento.** Python es el **oráculo** (el valor tiene que coincidir) y la **referencia de
tiempo**: el objetivo no es ganarle sino acercarse a un lenguaje que hoy es la medida. Cada
operación existe como programa de Zymbol y gemelo de Python que imprimen lo mismo (`gap.py`,
en `ZyBigBench.zip`); cada programa **cronometra su propio trabajo por dentro**, sin arranque
del intérprete ni restas. Se mide con n y con 2n: si la brecha **crece** al doblar n, la
diferencia es de algoritmo y no de constante.

**Valores.** La VM coincide con Python en **52 de 52** mediciones, y el árbol también.
No hay ninguna salida distinta.

**Los gemelos de Python corren dentro de una función.** Es lo normal en CPython (las variables
locales son más rápidas que las globales). Mi primera pasada los puso a nivel de módulo y daba
a Zymbol cifras mucho mejores de las que merece: el listón era demasiado fácil. Eso también
afecta a PERF-06 (ver abajo).

### Donde Zymbol está a un factor constante de Python (sin defecto de algoritmo)

La brecha no crece al doblar n. Zymbol va **entre 1,3 y 4,6 veces más lento** en casi todo,
y **más rápido** en `sort_builtin` (0,5) e `print_lines` (0,4).

| Operación | n | Python ms | VM ms | árbol ms | Brecha VM/Python (n → 2n) |
|---|---|---:|---:|---:|---:|
| `arr_append` | 1 000 000→2 000 000 | 67 | 115 | 393 | 2.0 → 1.7 |
| `arr_read` | 500 000→1 000 000 | 39 | 84 | 342 | 2.2 → 2.2 |
| `arr_foreach` | 500 000→1 000 000 | 23 | 60 | 238 | 2.7 → 2.6 |
| `map_filter_reduce` | 500 000→1 000 000 | 130 | 218 | 1092 | 1.7 → 1.7 |
| `sort_comparator` | 50 000→100 000 | 119 | 230 | 1145 | 1.4 → 1.9 |
| `sort_builtin` | 500 000→1 000 000 | 247 | 120 | 400 | 0.5 → 0.5 |
| `str_interp` | 500 000→1 000 000 | 90 | 192 | 551 | 2.1 → 2.1 |
| `call_overhead` | 1 000 000→2 000 000 | 92 | 174 | 1471 | 1.9 → 1.9 |
| `closure_create_call` | 500 000→1 000 000 | 142 | 194 | 1594 | 1.3 → 1.4 |
| `match_range` | 1 000 000→2 000 000 | 135 | 208 | 328 | 1.5 → 1.5 |
| `print_lines` | 100 000→200 000 | 573 | 211 | 254 | 0.4 → 0.4 |
| `dict_lookup` | 2 000→4 000 | 6 | 18 | 75 | 4.6 → 3.0 |

> **Aviso sobre `dict_lookup` en esta tabla:** lee siempre la **primera** clave, así que sale
> «sano» (1,6–4,6) y no lo es; la lectura de la última clave crece con el tamaño (PERF-03).

### Donde la brecha crece con el tamaño (el defecto es de algoritmo)

Ordenado por la brecha con n grande. «VM/árbol» dice si el árbol ya tiene el camino rápido.

| Operación | n | Python ms | VM ms | árbol ms | Brecha VM/Python (n → 2n) |
|---|---|---:|---:|---:|---:|
| `arr_update_one` | 50 000→100 000 | <1 | 907 | <1 | 10 256 → 19 298 |
| `dict_update_existing` | 2 000→4 000 | <1 | 229 | 303 | 3 767 → 7 156 |
| `str_slice_small` | 73 728→147 456 | <1 | 256 | 300 | 1 183 → 2 207 |
| `arr_update_each` | 8 000→16 000 | <1 | 1073 | 4 | 846 → 1 774 |
| `dict_insert` | 4 000→8 000 | 2 | 2148 | 2851 | 655 → 1 393 |
| `arr_remove_last` | 8 000→16 000 | 1 | 555 | 3 | 305 → 551 |
| `str_iter` | 147 456→294 912 | 5 | 2117 | 59 | 223 → 417 |
| `str_len` | 73 728→147 456 | <1 | 68 | 147 | 50 → 100 |
| `str_concat` | 64 000→128 000 | 4 | 352 | 1971 | 26 → 78 |

**Lectura para priorizar.**

1. **La VM es mucho más lenta que su propio árbol en tres casos** (`arr_update_each` ~270 veces,
   `arr_remove_last` ~185, `str_iter` ~36): el camino rápido ya existe en el árbol, y es donde
   hay más por ganar y menos riesgo. Son PERF-01, 02 y 04.
2. **`dict_insert`, `dict_update_existing`, `str_len`, `str_slice_small` y `str_concat`** son
   lentos en los dos motores: el arreglo pasa por la operación en sí (PERF-03, 05 y 06).
3. Con **todo lo demás**, Zymbol está a 1,3–4,6× de Python en la VM (la cifra alta es la
   lectura de diccionario con pocas claves), y eso es una cuestión de constante, no de algoritmo.

**Límites de esta pasada.** Tres ejecuciones por tamaño y mediana; el reloj de Zymbol
(`std/time`) tiene resolución de 1 ms, así que las brechas con VM por debajo de 5 ms se
marcan `~`. Una máquina, binarios sin LTO, Python 3.12.3. Los gemelos son Python plano, sin
`numpy` ni PyPy.

---

## Operaciones sin defecto (crecimiento lineal medido)

`arr_append` (b = 0,87–1,04, 800 000 añadidos en 44 ms), `arr_read`, `arr_foreach`,
`map_filter_reduce`, `sort_builtin` (b = 1,00–1,13), `sort_comparator` (b = 1,08 en la VM
nueva), `str_interp`, `call_overhead`, `closure_create_call`, `match_range`, `print_lines` y
`recursion_depth` en la VM (b = 1,08). Y por llamada, planas: `$#` **de un arreglo** y la lectura por índice de un arreglo en la VM, y pasar un arreglo a una función (la lectura de diccionario NO es plana: ver PERF-03)
(`b ≈ 0` en el árbol; en la VM tan pequeño que no se pudo medir).

## Señales débiles que no confirmé

En el árbol: `arr_slice_small` (`b = 1,38`, 139 ms), `arr_len` (`b = 0,79`) y `arr_get_middle`
(`b = 0,56`). Son tiempos de menos de 210 ms con 6 400 000 elementos, y podrían ser efectos de
memoria o caché. **No las cuento como defectos.**

## Límites de esta medición

- Una máquina, un contenedor compartido, un solo binario compilado sin LTO.
- El barrido mide CPU de procesos completos y, para las operaciones «por llamada», **resta
  una ejecución sin el trabajo caliente**; esa resta es ruidosa cuando la construcción es
  lenta (PERF-03 en la pasada 1, retirada arriba). Las cifras de PERF-03, 04 y 05 que se
  citan con detalle salen de temporizadores **dentro del programa** (`std/time`).
- Las causas de PERF-01 a 05, 07 y 08 están **confirmadas** (código, commit del autor o prueba
  independiente; ver «Causas confirmadas»). Siguen siendo hipótesis: por qué `s = s "x"` sigue
  siendo cuadrático en la VM (no leí esa ruta) y si el asignador explica también el 2,3× de
  interpolación y el 1,6× de cierres (coincide con la medida de objetos pequeños, pero no la
  probé sobre esas operaciones).
- Falta probar: `$+` de arreglos de arreglos, `$-` por el principio y el medio, cadenas muy
  largas con caracteres no ASCII, y el coste de `$~` profundo (`m[i>j]$~ x`).
