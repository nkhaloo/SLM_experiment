procedure getBasicInfo
	
		# Get time of interval label & interval label 
    		start 			= Get start time
            end 			= Get end time
			
			if textgrid == 1
				n_syllables = Get number of points... target_tier_number
			endif

			interval  	= (end-start)/numintervals
			utterance_duration = end - start
			start_realtime = start
			end_realtime = end


endproc