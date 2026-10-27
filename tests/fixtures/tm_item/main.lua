-- Test stub: one TM Case item at index 960 (tests/tm_case_test.lua; 950-954 are the Exp. Candies).
return function(mod)
  mod.content.items:register("TM_TEST", {
    id = "TM_TEST", name = "TM TEST", index = 960, pocket = "TM_CASE", price = 3000,
  })
end
