From the repository root, run `opam exec -- ./run-tests nodb-unit-tests`.

To run only a single test, first find the test name using:

`opam exec -- ./run-tests nodb-unit-tests -list-test`

And then run:

`opam exec -- ./run-tests nodb-unit-tests -only-test '<test name>' -v true`
