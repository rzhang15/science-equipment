program detect_position_outcomes
    cap use n_first_ppr in 1 using ../external/prepped_samples/es_all_jrnls_r1_r2, clear
    global POSITION_OUTCOMES_AVAIL = cond(_rc == 0, 1, 0)
end
