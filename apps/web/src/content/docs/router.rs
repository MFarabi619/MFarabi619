#[derive(
    Clone,
    Copy,
    dioxus_router::Routable,
    PartialEq,
    Eq,
    Hash,
    Debug,
    serde::Serialize,
    serde::Deserialize
)]
pub enum BookRoute {
    #[route("/#:section")]
    Index { section: IndexSection },
}
impl BookRoute {
    /// Get the markdown for a page by its ID
    pub const fn page_markdown(id: use_mdbook::mdbook_shared::PageId) -> &'static str {
        match id.0 {
            0usize => "# Introduction\n\nWork-in-progress.",
            _ => panic!("Invalid page ID:"),
        }
    }
    pub fn sections(&self) -> &'static [use_mdbook::mdbook_shared::Section] {
        &self.page().sections
    }
    pub fn page(&self) -> &'static use_mdbook::mdbook_shared::Page<Self> {
        LAZY_BOOK.get_page(self)
    }
    pub fn page_id(&self) -> use_mdbook::mdbook_shared::PageId {
        match self {
            BookRoute::Index { .. } => use_mdbook::mdbook_shared::PageId(0usize),
        }
    }
}
impl Default for BookRoute {
    fn default() -> Self {
        BookRoute::Index {
            section: IndexSection::Empty,
        }
    }
}
pub static LAZY_BOOK: use_mdbook::Lazy<use_mdbook::mdbook_shared::MdBook<BookRoute>> = use_mdbook::Lazy::new(||
{
    {
        let mut page_id_mapping = ::std::collections::HashMap::new();
        let mut pages = Vec::new();
        let __push_page_0: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    0usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Introduction".to_string(),
                            url: BookRoute::Index {
                                section: IndexSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Introduction".to_string(),
                                    id: "introduction".to_string(),
                                    level: 1usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(0usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::Index {
                        section: IndexSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(0usize),
                );
        };
        __push_page_0(&mut pages, &mut page_id_mapping);
        ::use_mdbook::mdbook_shared::MdBook {
            summary: ::use_mdbook::mdbook_shared::Summary {
                title: Some("Summary".to_string()),
                prefix_chapters: vec![],
                numbered_chapters: vec![
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Introduction".to_string(),
                        location: Some(BookRoute::Index {
                            section: IndexSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![1u32]),
                        ),
                        nested_items: vec![],
                    }),
                ],
                suffix_chapters: vec![],
            },
            pages: pages.into_iter().collect(),
            page_id_mapping,
        }
    }
});
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum IndexSection {
    #[default]
    Empty,
    Introduction,
}
impl std::str::FromStr for IndexSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "introduction" => Ok(Self::Introduction),
            _ => Err("Invalid section name. Expected one of IndexSectionintroduction"),
        }
    }
}
impl std::fmt::Display for IndexSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::Introduction => f.write_str("introduction"),
        }
    }
}
#[component(no_case_check)]
pub fn Index(section: IndexSection) -> Element {
    rsx! {
        h1 { id : "introduction", Link { to : BookRoute::Index { section :
        IndexSection::Introduction, }, class : "header", "Introduction" } } p {
        "Work-in-progress." }
    }
}

use super::*;
