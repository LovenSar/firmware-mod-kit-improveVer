import common
from smartsig import SmartSignature

class MagicFilter:
	'''
	Class to filter libmagic results based on include/exclude rules and false positive detection.
	An instance of this class is available via the Binwalk.filter object.

	Example code which creates include, exclude, and grep filters before running a Binwalk scan:

		import binwalk

		bw = binwalk.Binwalk()

		# Include all signatures whose descriptions contain the string 'filesystem' in the first line of the signature, even if those signatures are normally excluded.
		# Note that if exclusive=False was specified, this would merely add these signatures to the default signatures.
		# Since exclusive=True (the default) has been specified, ONLY those matching signatures will be loaded; all others will be ignored.
		bw.filter.include('filesystem')

		# Exclude all signatures whose descriptions contain the string 'jffs2', even if those signatures are normally included.
		# In this case, we are now searching for all filesystem signatures, except JFFS2.
		bw.filter.exclude('jffs2')

		# Add a grep filter. Unlike the include and exclude filters, it does not affect which results are returned by Binwalk.scan(), but it does affect which results
		# are printed by Binwalk.display.results(). This is particularly useful for cases like the bincast scan, where multiple lines of results are returned per offset,
		# but you only want certian ones displayed. In this case, only file systems whose description contain the string '2012' will be displayed.
		bw.filter.grep(filters=['2012'])

		bw.scan('firmware.bin')
	'''

	# If the result returned by libmagic is "data" or contains the text
	# 'invalid' or a backslash are known to be invalid/false positives.
	DATA_RESULT = "data"
	INVALID_RESULTS = ["invalid", "\\"]
	INVALID_RESULT = "invalid"
	NON_PRINTABLE_RESULT = "\\"

	FILTER_INCLUDE = 0
	FILTER_EXCLUDE = 1

	def __init__(self, show_invalid_results=False):
		'''
		Class constructor.

		@show_invalid_results - Set to True to display results marked as invalid.

		Returns None.
		'''
		self.filters = []
		self.grep_filters = []
		self.show_invalid_results = show_invalid_results
		self.exclusive_filter = False
		self.smart = SmartSignature(self)

	def include(self, match, exclusive=True):
		'''
		Adds a new filter which explicitly includes results that contain
		the specified matching text.

		@match     - Case insensitive text, or list of texts, to match.
		@exclusive - If True, then results that do not explicitly contain
			     a FILTER_INCLUDE match will be excluded. If False,
			     signatures that contain the FILTER_INCLUDE match will
			     be included in the scan, but will not cause non-matching
			     results to be excluded.
		
		Returns None.
		'''
		include_filter = {
				'type'		: self.FILTER_INCLUDE,
				'filter'	: ''
		}

		if type(match) != type([]):
			matches = [match]
		else:
			matches = match

		for m in matches:
			if m:
				if exclusive and not self.exclusive_filter:
					self.exclusive_filter = True

				include_filter['filter'] = m.lower()
				self.filters.append(include_filter)

	def exclude(self, match):
		'''
		Adds a new filter which explicitly excludes results that contain
		the specified matching text.

		@match - Case insensitive text, or list of texts, to match.
		
		Returns None.
		'''
		exclude_filter = {
				'type'		: self.FILTER_EXCLUDE,
				'filter'	: ''
		}

		if type(match) != type([]):
			matches = [match]
		else:
			matches = match

		for m in matches:
			if m:
				exclude_filter['filter'] = m.lower()
				self.filters.append(exclude_filter)

	def filter(self, data):
		'''
		Checks to see if a given string should be excluded from or included in the results.
		Called internally by Binwalk.scan().

		@data - String to check.

		Returns FILTER_INCLUDE if the string should be included.
		Returns FILTER_EXCLUDE if the string should be excluded.
		'''
		data = data.lower()

		# Loop through the filters to see if any of them are a match. 
		# If so, return the registered type for the matching filter (FILTER_INCLUDE | FILTER_EXCLUDE). 
		for f in self.filters:
			if f['filter'] in data:
				return f['type']

		# If there was not explicit match and exclusive filtering is enabled, return FILTER_EXCLUDE.
		if self.exclusive_filter:
			return self.FILTER_EXCLUDE

		return self.FILTER_INCLUDE

	def invalid(self, data):
		'''
		Checks if the given string contains invalid data.
		Called internally by Binwalk.scan().

		@data - String to validate.

		Returns True if data is invalid, False if valid.
		'''
		# A result of 'data' is never ever valid.
		if data == self.DATA_RESULT:
			return True

		# If showing invalid results, just return False.
		if self.show_invalid_results:
			return False

		# Don't include quoted strings or keyword arguments in this search, as 
		# strings from the target file may legitimately contain the INVALID_RESULT text.
		if self.INVALID_RESULT in common.strip_quoted_strings(self.smart._strip_tags(data)):
			return True

		# There should be no non-printable data in any of the data
		if self.NON_PRINTABLE_RESULT in data:
			return True

		return False

	def grep(self, data=None, filters=[]):
		'''
		Add or check case-insensitive grep filters against the supplied data string.

		@data    - Data string to check grep filters against. Not required if filters is specified.
		@filters - Filter, or list of filters, to add to the grep filters list. Not required if data is specified.

		Returns None if data is not specified.
		If data is specified, returns True if the data contains a grep filter, or if no grep filters exist.
		If data is specified, returns False if the data does not contain any grep filters.
		'''
		# Add any specified filters to self.grep_filters
		if filters:
			if type(filters) != type([]):
				gfilters = [filters]
			else:
				gfilters = filters

			for gfilter in gfilters:
				# Filters are case insensitive
				self.grep_filters.append(gfilter.lower())

		# Check the data against all grep filters until one is found
		if data is not None:
			# If no grep filters have been created, always return True
			if not self.grep_filters:
				return True

			# Filters are case insensitive
			data = data.lower()

			# If a filter exists in data, return True
			for gfilter in self.grep_filters:
				if gfilter in data:
					return True

			# Else, return False
			return False
	
		return None

	def clear(self):
		'''
		Clears all include, exclude and grep filters.
		
		Retruns None.
		'''
		self.filters = []
		self.grep_filters = []
