use heapless::{String, Vec};

/// Configuration for command history
#[derive(Clone, Copy)]
pub struct HistoryConfig {
    /// Maximum number of history entries
    pub max_entries: usize,
    /// Whether to deduplicate consecutive identical commands
    pub deduplicate: bool,
}

impl Default for HistoryConfig {
    fn default() -> Self {
        Self {
            max_entries: 10,
            deduplicate: true,
        }
    }
}

/// Command history manager
pub struct History<const BUF_SIZE: usize> {
    entries: Vec<String<BUF_SIZE>, 16>,
    config: HistoryConfig,
    current_index: Option<usize>,
}

impl<const BUF_SIZE: usize> History<BUF_SIZE> {
    /// Create a new history manager
    pub fn new(config: HistoryConfig) -> Self {
        Self {
            entries: Vec::new(),
            config,
            current_index: None,
        }
    }

    /// Add a command to history
    pub fn add(&mut self, command: &str) -> Result<(), ()> {
        // Skip empty commands
        if command.trim().is_empty() {
            return Ok(());
        }

        // Check for deduplication
        if self.config.deduplicate {
            if let Some(last) = self.entries.last() {
                if last.as_str() == command {
                    return Ok(());
                }
            }
        }

        let entry = String::try_from(command).map_err(|_| ())?;

        // If at capacity, remove oldest
        if self.entries.len() >= self.config.max_entries {
            self.entries.remove(0);
        }

        self.entries.push(entry).map_err(|_| ())?;
        self.current_index = None;
        Ok(())
    }

    /// Get the previous command in history
    pub fn previous(&mut self) -> Option<&str> {
        if self.entries.is_empty() {
            return None;
        }

        let new_index = match self.current_index {
            None => self.entries.len() - 1,
            Some(0) => return Some(&self.entries[0]),
            Some(i) => i - 1,
        };

        self.current_index = Some(new_index);
        Some(&self.entries[new_index])
    }

    /// Get the next command in history
    pub fn next(&mut self) -> Option<&str> {
        match self.current_index {
            None => None,
            Some(i) if i >= self.entries.len() - 1 => {
                self.current_index = None;
                None
            }
            Some(i) => {
                self.current_index = Some(i + 1);
                Some(&self.entries[i + 1])
            }
        }
    }

    /// Reset the history navigation position
    pub fn reset_position(&mut self) {
        self.current_index = None;
    }

    /// Get the number of entries in history
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Check if history is empty
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Clear all history
    pub fn clear(&mut self) {
        self.entries.clear();
        self.current_index = None;
    }

    /// Get an iterator over history entries (oldest to newest)
    pub fn iter(&self) -> impl Iterator<Item = &str> {
        self.entries.iter().map(|s| s.as_str())
    }

    /// Get an iterator over history entries in reverse (newest to oldest)
    pub fn iter_rev(&self) -> impl Iterator<Item = &str> {
        self.entries.iter().rev().map(|s| s.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_history_add() {
        let mut history = History::<64>::new(HistoryConfig::default());
        history.add("command1").unwrap();
        history.add("command2").unwrap();
        assert_eq!(history.len(), 2);
    }

    #[test]
    fn test_history_deduplicate() {
        let mut history = History::<64>::new(HistoryConfig {
            deduplicate: true,
            ..Default::default()
        });
        history.add("command1").unwrap();
        history.add("command1").unwrap();
        assert_eq!(history.len(), 1);
    }

    #[test]
    fn test_history_navigation() {
        let mut history = History::<64>::new(HistoryConfig::default());
        history.add("cmd1").unwrap();
        history.add("cmd2").unwrap();
        history.add("cmd3").unwrap();

        assert_eq!(history.previous(), Some("cmd3"));
        assert_eq!(history.previous(), Some("cmd2"));
        assert_eq!(history.next(), Some("cmd3"));
        assert_eq!(history.next(), None);
    }
}