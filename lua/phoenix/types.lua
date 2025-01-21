---Configuration for weighting different factors in word scoring
---@class WeightConfig
---@field recency number Weight for recency in scoring (0-1). Higher values favor recently used words more strongly
---@field frequency number Weight for frequency in scoring (0-1). Higher values favor frequently used words more strongly

---Core dictionary configuration
---@class DictionaryConfig
---@field capacity number Maximum number of words to store in the dictionary. Higher values provide better completions but use more memory
---@field min_word_length number Minimum length for a word to be considered for the dictionary. Lower values catch more words but may include noise
---@field word_pattern string Pattern for word split

---Configuration for completion
---@class CompletionConfig
---@field decay_minutes integer Time period for decay calculation
---@field weights WeightConfig Scoring weights configuration for ranking completion candidates

---Configuration for dictionary cleanup process
---@class CleanupConfig
---@field cleanup_batch_size number Number of words to process in each cleanup batch. Higher values are faster but may cause more noticeable pauses
---@field frequency_threshold number Minimum frequency relative to max frequency to keep a word (0-1). Higher values are more aggressive in removing rare words
---@field collection_batch_size number Number of words to collect before yielding control. Balance between cleanup speed and responsiveness
---@field rebuild_batch_size number Number of words to rebuild before yielding control. Balance between rebuild speed and responsiveness
---@field idle_timeout_ms number Time to wait after changes before starting cleanup (milliseconds). Prevents cleanup during rapid edits
---@field cleanup_ratio number Dictionary size ratio that triggers cleanup (0-1). Higher values mean more frequent cleanups
---@field enable_notify boolean Enable notify when cleanup dictionary

---Configuration for file system scanning
---@class ScannerConfig
---@field scan_batch_size number Number of items to process in each scan batch. Higher values improve speed but may cause stuttering
---@field cache_duration_ms number How long to cache scan results (milliseconds). Higher values improve performance but may show stale results
---@field throttle_delay_ms number Delay between processing updates (milliseconds). Prevents excessive CPU usage during rapid changes
---@field ignore_patterns string[] Patterns for files/directories to ignore during scanning. Improves performance by skipping irrelevant items

---Main configuration for Phoenix
---@class PhoenixConfig
---@field filetypes string[] List of filetypes to enable Phoenix for. Use {'*'} for all filetypes
---@field dict DictionaryConfig Settings controlling the core dictionary behavior
---@field completion CompletionConfig Settings controlling the core dictionary behavior
---@field cleanup CleanupConfig Settings controlling how and when dictionary cleanup occurs
---@field scanner ScannerConfig Settings controlling file system scanning behavior
