use core::{error::Error, fmt};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GPIOError {
    InvalidBuilder,
    InvalidPinIndex,
    NotOutput,
}

impl fmt::Display for GPIOError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::InvalidBuilder => "GPIO is unavailable or its pin count is invalid.",
            Self::InvalidPinIndex => "Pin index out of bounds.",
            Self::NotOutput => "Configure the pin as an output before writing.",
        })
    }
}

impl Error for GPIOError {}
