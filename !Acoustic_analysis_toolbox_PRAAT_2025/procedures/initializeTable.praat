procedure initializeTable
	
	Create Table with column names... acoustic_measurements 1 Filename (Real)Time_Start (Real)Time_End  Duration NumSyllables Intensity HNR AlphaRatio Mean_f0 Sd_f0 Max_F0 speakingrate articulationrate npause asd
	for i to numintervals
		Append column... Mean_f0_Interval_'i'
	endfor

endproc