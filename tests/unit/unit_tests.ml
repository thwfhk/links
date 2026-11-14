open OUnit2

let suites =
  "all"
  >::: [
         ("ir"
         >:::
         let open Links_ir_unit_tests in
         [
           Binding.suite;
           Functions.suite;
           Effects.suite;
           Quantifiers.suite;
           Closures.suite;
           Variants.suite;
         ]);
         Modal_effects_tests.suite;
         Modal_scope_tests.suite;
         Fresco_patterns_tests.suite;
         Fresco_tests.suite;
       ]

let () = run_test_tt_main suites
