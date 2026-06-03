procedure addSoundBuffer
	
	# First create silence the duration of the buffer
	Create Sound from formula: "silence", 1, 0.0, noise_buffer, fs, "0"
	Rename... silence

	# Append buffer to end of original sound file to account for the noise buffer (e.g., 150ms)
	selectObject: 'curr_sound'
	plusObject: "Sound silence"
	Concatenate
	Rename... sound_plus_buffer
endproc