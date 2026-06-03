procedure getHNR

	selectObject: "Sound 'object_name$'"
	noprogress To Harmonicity (cc): 0.01, f0_minimum, 0.1, 1.0

	meanHNR = Get mean: 0, 0

endproc