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
           ModalEffects.suite;
           ModalTypes.suite;
           ModalTypeTraversal.suite;
           FrescoKind.suite;
           FrescoWellformed.suite;
           FrescoContext.suite;
           FrescoScope.suite;
           FrescoExport.suite;
           FrescoSkeleton.suite;
           FrescoSkeletonOps.suite;
           FrescoSkeletonScope.suite;
           FrescoRecursive.suite;
           FrescoCompare.suite;
           FrescoConsistency.suite;
           FrescoSubtype.suite;
           FrescoJoin.suite;
           FrescoElaborate.suite;
           Fresco_source_tests.suite;
           Fresco_actor_tests.suite;
           Fresco_session_tests.suite;
           Fresco_cp_tests.suite;
           Fresco_modal_source_tests.suite;
           Fresco_effect_ir_tests.suite;
           ModalSyntax.suite;
           ModalDeclarations.suite;
           ModalResolution.suite;
           Quantifiers.suite;
           Closures.suite;
           Variants.suite;
           Runtime_types_tests.suite;
         ]);
       ]

let () = run_test_tt_main suites
