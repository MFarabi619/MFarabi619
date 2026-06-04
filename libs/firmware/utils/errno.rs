use core::fmt;
use core::num::NonZeroI32;

#[derive(Copy, Clone, PartialEq, Eq)]
pub struct Errno(NonZeroI32);

impl Errno {
    pub fn raw(self) -> i32 {
        self.0.get()
    }
}

impl fmt::Display for Errno {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match -self.raw() {
            1 => write!(f, "EPERM (operation not permitted)"),
            2 => write!(f, "ENOENT (no such entry)"),
            5 => write!(f, "EIO"),
            11 => write!(f, "EAGAIN (try again)"),
            12 => write!(f, "ENOMEM (out of memory)"),
            16 => write!(f, "EBUSY"),
            17 => write!(f, "EEXIST"),
            19 => write!(f, "ENODEV (no such device)"),
            22 => write!(f, "EINVAL (invalid argument)"),
            104 => write!(f, "ECONNRESET"),
            110 => write!(f, "ETIMEDOUT"),
            111 => write!(f, "ECONNREFUSED"),
            113 => write!(f, "EHOSTUNREACH"),
            115 => write!(f, "EINPROGRESS"),
            other => write!(f, "errno {other}"),
        }
    }
}

impl fmt::Debug for Errno {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Errno({})", self.raw())
    }
}

pub trait IntoResult {
    fn ok(self) -> Result<(), Errno>;
}

impl IntoResult for i32 {
    fn ok(self) -> Result<(), Errno> {
        if self < 0 {
            // SAFETY: self < 0 implies non-zero.
            Err(Errno(unsafe { NonZeroI32::new_unchecked(self) }))
        } else {
            Ok(())
        }
    }
}
