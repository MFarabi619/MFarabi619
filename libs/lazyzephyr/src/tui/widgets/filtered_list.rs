use alloc::{string::String, vec::Vec};

use ratatui::widgets::ListState;

#[derive(Debug)]
pub struct FilteredListState {
    pub list:   ListState,
    pub filter: String,
}

impl Default for FilteredListState {
    fn default() -> Self { Self::new() }
}

impl FilteredListState {
    pub fn new() -> Self {
        Self { list: ListState::default().with_selected(Some(0)), filter: String::new() }
    }

    pub fn view<'a, T, F>(&'a self, items: &'a [T], score: F) -> FilteredListView<'a, T, F>
    where F: Fn(&T, &str) -> Option<i64>,
    { FilteredListView { state: self, items, score } }

    pub fn step(&mut self, n: usize, dir: isize) {
        if n == 0 { return; }
        let cur = self.list.selected().unwrap_or(0) as isize;
        self.list.select(Some((cur + dir).rem_euclid(n as isize) as usize));
    }

    pub fn selected(&self) -> Option<usize> { self.list.selected() }
    pub fn select_first(&mut self) { self.list.select_first(); }
    pub fn select_last(&mut self)  { self.list.select_last(); }
}

pub struct FilteredListView<'a, T, F> {
    state: &'a FilteredListState,
    items: &'a [T],
    score: F,
}

impl<'a, T, F: Fn(&T, &str) -> Option<i64>> FilteredListView<'a, T, F> {
    pub fn indices(&self) -> Vec<usize> {
        if self.state.filter.is_empty() {
            return (0..self.items.len()).collect();
        }
        let mut scored: Vec<(usize, i64)> = self.items.iter().enumerate()
            .filter_map(|(i, t)| (self.score)(t, &self.state.filter).map(|s| (i, s)))
            .collect();
        scored.sort_by_key(|(_, s)| core::cmp::Reverse(*s));
        scored.into_iter().map(|(i, _)| i).collect()
    }

    pub fn len(&self) -> usize { self.indices().len() }

    pub fn is_empty(&self) -> bool { self.len() == 0 }

    pub fn selected_index(&self) -> Option<usize> {
        self.indices().into_iter().nth(self.state.list.selected()?)
    }

    pub fn selected(&self) -> Option<&'a T> {
        self.selected_index().and_then(|i| self.items.get(i))
    }

    pub fn iter(&self) -> impl Iterator<Item = (usize, &'a T)> + '_ {
        self.indices().into_iter().filter_map(|i| self.items.get(i).map(|t| (i, t)))
    }
}
