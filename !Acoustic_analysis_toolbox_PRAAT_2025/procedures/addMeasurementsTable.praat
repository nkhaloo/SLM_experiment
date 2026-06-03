procedure addMeasurementsTable
	
	###### ADD TO OUTPUT TABLE ###############################################################
				### Add to table

				selectObject: "Table acoustic_measurements"
				Append row
				Set string value... table_row_counter Filename 'wavfile$'
				
				Set numeric value... table_row_counter (Real)Time_Start 'start_realtime'
				Set numeric value... table_row_counter (Real)Time_End 'end_realtime'
				Set numeric value... table_row_counter Duration 'utterance_duration'

				if textgrid == 1
					Set numeric value... table_row_counter NumSyllables 'n_syllables'
				endif 

				if "'mean_intensity'" = "--undefined--"
					Set string value... table_row_counter Intensity "NA"
				else
					Set numeric value... table_row_counter Intensity 'mean_intensity'
				endif

				if "'meanHNR'" = "--undefined--"
					Set string value... table_row_counter HNR "NA"
				else
					Set numeric value... table_row_counter HNR 'meanHNR'
				endif

				if "'alpharatio'" = "--undefined--"
					Set string value... table_row_counter AlphaRatio "NA"
				else
					Set numeric value... table_row_counter AlphaRatio 'alpharatio'
				endif



					#### ADD IN INFO TO TABLE
					#selectObject: "Table acoustic_measurements"
					Set string value... table_row_counter Mean_f0 'overall_mean_f0'
					Set string value... table_row_counter Sd_f0 'overall_sd_f0'
					Set string value... table_row_counter Max_F0 'max_f0'


     
			table_row_counter = table_row_counter + 1

endproc