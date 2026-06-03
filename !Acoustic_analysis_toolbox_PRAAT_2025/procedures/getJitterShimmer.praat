procedure getJitterShimmer

	selectObject: "Sound 'object_name$'"
	noprogress To PointProcess (periodic, cc): f0_minimum, f0_maximum
	
	# Local jitter (normalized by mean period) # default settings
	local_jitter = Get jitter (local): 0, 0, 0.0001, 0.02, 1.3

	plusObject: "Sound 'object_name$'"
	# Local shimmer; default settings
	local_shimmer = Get shimmer (local): 0, 0, 0.0001, 0.02, 1.3, 1.6

endproc