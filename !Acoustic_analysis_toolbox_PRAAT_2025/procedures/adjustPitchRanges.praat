procedure adjustPitchRanges
	
if constraingender$ = "yes" 

	if gender$ = "male"
		f0_minimum = 78
		f0_maximum = 150

	endif

	if gender$ = "kid"
		f0_minimum = 150
		f0_maximum = 450

	endif

	if gender$ = "female"
		f0_minimum = 150
		f0_maximum = 350
	endif

else 

	f0_minimum = 78
	f0_maximum = 350

endif


endproc