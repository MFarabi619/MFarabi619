use std::cell::RefCell;
use std::rc::Rc;
use std::time::{Duration, Instant};

use embedded_graphics_simulator::{SimulatorEvent, sdl2::Keycode};

pub struct Button<'a> {
    events: Rc<RefCell<Vec<SimulatorEvent>>>,
    last_event: Instant,
    debounce: Duration,
    _marker: core::marker::PhantomData<&'a ()>,
}

impl<'a> Button<'a> {
    pub fn new(events: Rc<RefCell<Vec<SimulatorEvent>>>, debounce: Duration) -> Self {
        Self {
            events,
            last_event: Instant::now(),
            debounce,
            _marker: core::marker::PhantomData,
        }
    }

    pub fn was_pressed(&mut self) -> bool {
        let now = Instant::now();
        let drained: Vec<SimulatorEvent> = self.events.borrow_mut().drain(..).collect();
        for event in drained {
            if let SimulatorEvent::KeyDown { keycode, .. } = event {
                if matches!(
                    keycode,
                    Keycode::Space | Keycode::Return | Keycode::Right | Keycode::Tab
                ) && now - self.last_event >= self.debounce
                {
                    self.last_event = now;
                    return true;
                }
            }
        }
        false
    }
}
