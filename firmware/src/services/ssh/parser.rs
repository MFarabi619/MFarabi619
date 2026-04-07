use heapless::{String, Vec};

/// A parsed command with its arguments
#[derive(Debug, Clone)]
pub struct ParsedCommand<const MAX_ARGS: usize, const BUF_SIZE: usize> {
    /// The command name
    pub command: String<BUF_SIZE>,
    /// Command arguments
    pub args: Vec<String<BUF_SIZE>, MAX_ARGS>,
}

impl<const MAX_ARGS: usize, const BUF_SIZE: usize> ParsedCommand<MAX_ARGS, BUF_SIZE> {
    /// Get the command name
    pub fn name(&self) -> &str {
        &self.command
    }

    /// Get the number of arguments
    pub fn arg_count(&self) -> usize {
        self.args.len()
    }

    /// Get an argument by index
    pub fn arg(&self, index: usize) -> Option<&str> {
        self.args.get(index).map(|s| s.as_str())
    }

    /// Get all arguments joined by a separator
    pub fn args_joined(&self, separator: &str) -> Option<String<BUF_SIZE>> {
        if self.args.is_empty() {
            return Some(String::new());
        }

        let mut result = String::new();
        for (i, arg) in self.args.iter().enumerate() {
            if i > 0 {
                result.push_str(separator).ok()?;
            }
            result.push_str(arg).ok()?;
        }
        Some(result)
    }

    /// Get the entire command line (command + args)
    pub fn full_command(&self) -> Option<String<BUF_SIZE>> {
        let mut result = self.command.clone();
        for arg in &self.args {
            result.push(' ').ok()?;
            result.push_str(arg).ok()?;
        }
        Some(result)
    }
}

/// Command parser for splitting input into command and arguments
pub struct CommandParser;

impl CommandParser {
    /// Parse a command line into command and arguments
    ///
    /// Supports basic quote handling for arguments with spaces.
    pub fn parse<const MAX_ARGS: usize, const BUF_SIZE: usize>(
        input: &str,
    ) -> Result<ParsedCommand<MAX_ARGS, BUF_SIZE>, ParseError> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let mut parts = Vec::<String<BUF_SIZE>, MAX_ARGS>::new();
        let mut current = String::<BUF_SIZE>::new();
        let mut in_quotes = false;
        let mut chars = trimmed.chars().peekable();

        while let Some(c) = chars.next() {
            match c {
                '"' => {
                    in_quotes = !in_quotes;
                }
                ' ' if !in_quotes => {
                    if !current.is_empty() {
                        parts.push(current.clone()).map_err(|_| ParseError::TooManyArgs)?;
                        current.clear();
                    }
                }
                _ => {
                    current.push(c).map_err(|_| ParseError::ArgTooLong)?;
                }
            }
        }

        // Push final argument
        if !current.is_empty() {
            parts.push(current).map_err(|_| ParseError::TooManyArgs)?;
        }

        if parts.is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let command = parts.remove(0);
        let args = parts;

        Ok(ParsedCommand { command, args })
    }

    /// Simple split on whitespace (faster but no quote support)
    pub fn parse_simple<const MAX_ARGS: usize, const BUF_SIZE: usize>(
        input: &str,
    ) -> Result<ParsedCommand<MAX_ARGS, BUF_SIZE>, ParseError> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let mut parts = Vec::<String<BUF_SIZE>, MAX_ARGS>::new();
        
        for part in trimmed.split_whitespace() {
            let s = String::<BUF_SIZE>::try_from(part).map_err(|_| ParseError::ArgTooLong)?;
            parts.push(s).map_err(|_| ParseError::TooManyArgs)?;
        }

        if parts.is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let command = parts.remove(0);
        let args = parts;

        Ok(ParsedCommand { command, args })
    }

    /// Parse with a maximum number of splits (remaining text goes into last arg)
    pub fn parse_max_split<const MAX_ARGS: usize, const BUF_SIZE: usize>(
        input: &str,
        max_splits: usize,
    ) -> Result<ParsedCommand<MAX_ARGS, BUF_SIZE>, ParseError> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let mut parts = Vec::<String<BUF_SIZE>, MAX_ARGS>::new();
        let mut split_count = 0;
        let mut remaining = trimmed;

        while split_count < max_splits {
            if let Some(pos) = remaining.find(' ') {
                let (part, rest) = remaining.split_at(pos);
                let s = String::<BUF_SIZE>::try_from(part.trim()).map_err(|_| ParseError::ArgTooLong)?;
                parts.push(s).map_err(|_| ParseError::TooManyArgs)?;
                remaining = rest.trim_start();
                split_count += 1;
            } else {
                break;
            }
        }

        // Add remaining as final argument
        if !remaining.is_empty() {
            let s = String::<BUF_SIZE>::try_from(remaining).map_err(|_| ParseError::ArgTooLong)?;
            parts.push(s).map_err(|_| ParseError::TooManyArgs)?;
        }

        if parts.is_empty() {
            return Err(ParseError::EmptyInput);
        }

        let command = parts.remove(0);
        let args = parts;

        Ok(ParsedCommand { command, args })
    }
}

/// Errors that can occur during parsing
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ParseError {
    EmptyInput,
    TooManyArgs,
    ArgTooLong,
    UnclosedQuote,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_command() {
        let parsed: ParsedCommand<8, 64> = CommandParser::parse_simple("hello").unwrap();
        assert_eq!(parsed.name(), "hello");
        assert_eq!(parsed.arg_count(), 0);
    }

    #[test]
    fn test_parse_with_args() {
        let parsed: ParsedCommand<8, 64> =
            CommandParser::parse_simple("send 192.168.1.1 message").unwrap();
        assert_eq!(parsed.name(), "send");
        assert_eq!(parsed.arg_count(), 2);
        assert_eq!(parsed.arg(0), Some("192.168.1.1"));
        assert_eq!(parsed.arg(1), Some("message"));
    }

    #[test]
    fn test_parse_with_quotes() {
        let parsed: ParsedCommand<8, 64> =
            CommandParser::parse(r#"send peer "hello world""#).unwrap();
        assert_eq!(parsed.name(), "send");
        assert_eq!(parsed.arg_count(), 2);
        assert_eq!(parsed.arg(1), Some("hello world"));
    }

    #[test]
    fn test_parse_max_split() {
        let parsed: ParsedCommand<8, 128> =
            CommandParser::parse_max_split("broadcast this is a long message", 1).unwrap();
        assert_eq!(parsed.name(), "broadcast");
        assert_eq!(parsed.arg_count(), 1);
        assert_eq!(parsed.arg(0), Some("this is a long message"));
    }
}