procedure getAlphaRatio

	selectObject: "Sound 'object_name$'"
	noprogress To Spectrum: "yes"

	# Get lower frquencies (50-1000)
	lowEnergy = Get band energy: 50,1000

	# Get higher frequencies (1000-5000)
	highEnergy = Get band energy: 1000,5000

	# Compute alpha ratio in dB
	alpharatio = 10 * log10 (lowEnergy / highEnergy)

endproc