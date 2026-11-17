#include "render_grid.h"
#include "css_parser.h"
#include "document.h"
#include "html_tag.h"
#include <map>
#include <sstream>
#include <taffy/tree/taffy_tree/tree/Taffy.hpp>

namespace litehtml {
namespace {
namespace t = taffy;
using Track = t::NonRepeatedTrackSizingFunction;
using LP = t::LengthPercentage;

css_token_vector tokens(const element::ptr &el, const char *name) {
  const auto *tag = dynamic_cast<const html_tag *>(el.get());
  if (!tag)
    return {};
  const auto &p = tag->declared_property(name);
  if (!p.is<css_token_vector>())
    return {};
  auto values = p.get<css_token_vector>();
  values.erase(
      std::remove_if(values.begin(), values.end(),
                     [](const css_token &t) { return t.type == WHITESPACE; }),
      values.end());
  return values;
}
LP length(const css_token &token, const element::ptr &el) {
  if (token.type == PERCENTAGE)
    return LP::Percent(token.n.number / 100);
  if (token.type != DIMENSION)
    return LP::Length(0);
  int u = value_index(token.unit, css_units_strings, -1);
  if (u < 0)
    return LP::Length(0);
  return LP::Length(el->get_document()->to_pixels(
      css_length(token.n.number, static_cast<css_units>(u)),
      el->css().get_font_metrics(), 0));
}
Track single(const css_token &token, const element::ptr &el) {
  if (token.type == IDENT) {
    if (token.name == "min-content")
      return Track::MIN_CONTENT();
    if (token.name == "max-content")
      return Track::MAX_CONTENT();
    return Track::AUTO();
  }
  if (token.type == DIMENSION && token.unit == "fr")
    return t::fr<Track>(std::max(0.f, token.n.number));
  if (token.type == CV_FUNCTION) {
    auto args = parse_comma_separated_list(token.value);
    for (auto &arg : args)
      arg.erase(std::remove_if(arg.begin(), arg.end(),
                  [](const css_token &v) { return v.type == WHITESPACE; }), arg.end());
    if (token.name == "minmax" && args.size() == 2 && !args[0].empty() &&
        !args[1].empty()) {
      const auto a = single(args[0][0], el), b = single(args[1][0], el);
      return Track({a.min, b.max});
    }
    if (token.name == "fit-content" && !args.empty() && !args[0].empty())
      return Track::fit_content(length(args[0][0], el));
    return Track::AUTO();
  }
  const auto v = length(token, el);
  return Track({t::MinTrackSizingFunction::Fixed(v),
                t::MaxTrackSizingFunction::Fixed(v)});
}
auto tracks(const element::ptr &el, const char *name) {
  t::GridTrackVec<t::TrackSizingFunction> out;
  for (const auto &v : tokens(el, name)) {
    if (v.type == SQUARE_BLOCK || (v.type == IDENT && v.name == "none"))
      continue;
    if (v.type == CV_FUNCTION && v.name == "repeat") {
      const auto args = parse_comma_separated_list(v.value);
      if (args.size() != 2 || args[0].empty())
        continue;
      const auto &count = args[0][0];
      auto repetition = t::GridTrackRepetition::Count(1);
      if (count.type == NUMBER && count.n.number >= 1)
        repetition = t::GridTrackRepetition::Count(
            static_cast<uint16_t>(std::min(1000.f, count.n.number)));
      else if (count.type == IDENT && count.name == "auto-fill")
        repetition = t::GridTrackRepetition::AutoFill();
      else if (count.type == IDENT && count.name == "auto-fit")
        repetition = t::GridTrackRepetition::AutoFit();
      else
        continue;
      t::GridTrackVec<Track> pattern;
      for (const auto &t : args[1])
        if (t.type != WHITESPACE && t.type != SQUARE_BLOCK)
          pattern.push_back(single(t, el));
      if (!pattern.empty())
        out.push_back(t::TrackSizingFunction::Repeat(repetition, pattern));
    } else
      out.push_back(t::TrackSizingFunction::Single(single(v, el)));
  }
  return out;
}
t::GridPlacement placement(css_token_vector v) {
  if (v.size() == 1 && v[0].type == NUMBER && v[0].n.number != 0 &&
      std::abs(v[0].n.number) <= 1000)
    return t::GridPlacement::Line(t::GridLine((int)v[0].n.number));
  if (v.size() == 2 && v[0].type == IDENT && v[0].name == "span" &&
      v[1].type == NUMBER && v[1].n.number >= 1 && v[1].n.number <= 1000)
    return t::GridPlacement::Span((int)v[1].n.number);
  return t::GridPlacement::Auto();
}
t::Line<t::GridPlacement> lines(const element::ptr &el, const string &prop) {
  const auto v = tokens(el, prop.c_str());
  auto slash = std::find_if(v.begin(), v.end(), [](const css_token &token) {
    return token.type == '/';
  });
  css_token_vector a(v.begin(), slash),
      b(slash == v.end() ? slash : slash + 1, v.end());
  const auto start = tokens(el, (prop + "-start").c_str()),
             end = tokens(el, (prop + "-end").c_str());
  return {placement(start.empty() ? a : start),
          placement(end.empty() ? b : end)};
}
struct Area {
  int left, top, right, bottom;
};
struct TemplateAreas {
  std::map<string, Area> named;
  int rows = 0, columns = 0;
};
TemplateAreas templateAreas(const element::ptr &el) {
  TemplateAreas result;
  std::vector<std::vector<string>> matrix;
  for (const auto &row : tokens(el, "grid-template-areas")) {
    if (row.type != STRING)
      return {};
    std::istringstream in(row.str);
    string name;
    std::vector<string> names;
    while (in >> name) {
      const int col = int(names.size()), r = int(matrix.size());
      names.push_back(name);
      if (name.find_first_not_of('.') == string::npos)
        continue;
      auto it = result.named.find(name);
      if (it == result.named.end())
        result.named[name] = {col + 1, r + 1, col + 2, r + 2};
      else {
        it->second.left = std::min(it->second.left, col + 1);
        it->second.right = std::max(it->second.right, col + 2);
        it->second.bottom = r + 2;
      }
    }
    if (names.empty() ||
        (!matrix.empty() && names.size() != matrix.front().size()))
      return {};
    matrix.push_back(std::move(names));
  }
  if (matrix.empty())
    return {};
  for (auto &pair : result.named) {
    auto &v = pair.second;
    for (int y = v.top - 1; y < v.bottom - 1; y++)
      for (int x = v.left - 1; x < v.right - 1; x++)
        if (matrix[y][x] != pair.first)
          return {};
  }
  result.rows = int(matrix.size());
  result.columns = int(matrix.front().size());
  return result;
}
t::Option<t::AlignItems> itemKeyword(const css_token_vector &values) {
  if (values.empty() || values.back().type != IDENT)
    return t::None;
  const auto &s = values.back().name;
  if (s == "center")
    return t::Some(t::AlignItems::Center);
  if (s == "end" || s == "self-end" || s == "flex-end")
    return t::Some(t::AlignItems::End);
  if (s == "start" || s == "self-start" || s == "flex-start")
    return t::Some(t::AlignItems::Start);
  if (s == "stretch")
    return t::Some(t::AlignItems::Stretch);
  return t::None;
}
t::Dimension dimension(const css_length &length) {
  if (length.is_predefined())
    return t::Dimension::Auto();
  if (length.units() == css_units_percentage)
    return t::Dimension::Percent(length.val() / 100);
  return t::Dimension::Length(length.val());
}
t::Option<t::AlignItems> alignment(int v) {
  switch (v & 255) {
  case flex_align_items_stretch:
    return t::Some(t::AlignItems::Stretch);
  case flex_align_items_start:
  case flex_align_items_flex_start:
    return t::Some(t::AlignItems::Start);
  case flex_align_items_end:
  case flex_align_items_flex_end:
    return t::Some(t::AlignItems::End);
  case flex_align_items_center:
    return t::Some(t::AlignItems::Center);
  case flex_align_items_baseline:
    return t::Some(t::AlignItems::Baseline);
  default:
    return t::None;
  }
}
} // namespace

rendered_width
render_item_grid::_render_content(pixel_t x, pixel_t y, bool,
                                  const containing_block_context &box,
                                  formatting_context *fmt) {
  auto tree = t::Taffy::New();
  auto style = t::Style::Default();
  style.display = t::Display::Grid();
  style.size.width = t::Dimension::Length(box.render_width);
  if (box.height.type != containing_block_context::cbc_value_type_auto)
    style.size.height = t::Dimension::Length(box.height - box_sizing_height());
  style.grid_template_columns = tracks(src_el(), "grid-template-columns");
  style.grid_template_rows = tracks(src_el(), "grid-template-rows");
  for (const auto &v : tokens(src_el(), "grid-auto-columns"))
    style.grid_auto_columns.push_back(single(v, src_el()));
  for (const auto &v : tokens(src_el(), "grid-auto-rows"))
    style.grid_auto_rows.push_back(single(v, src_el()));
  const auto areas = templateAreas(src_el());
  // Area templates establish an explicit grid even when no track sizes were
  // specified.
  if (style.grid_template_rows.empty())
    for (int i = 0; i < areas.rows; i++)
      style.grid_template_rows.push_back(t::TrackSizingFunction::AUTO());
  if (style.grid_template_columns.empty())
    for (int i = 0; i < areas.columns; i++)
      style.grid_template_columns.push_back(t::TrackSizingFunction::AUTO());
  const auto flow = tokens(src_el(), "grid-auto-flow");
  bool column = false, dense = false;
  for (auto &v : flow) {
    column |= v.type == IDENT && v.name == "column";
    dense |= v.type == IDENT && v.name == "dense";
  }
  style.grid_auto_flow =
      column
          ? (dense ? t::GridAutoFlow::ColumnDense() : t::GridAutoFlow::Column())
          : (dense ? t::GridAutoFlow::RowDense() : t::GridAutoFlow::Row());
  const auto gap = tokens(src_el(), "gap"),
             rowGap = tokens(src_el(), "row-gap"),
             columnGap = tokens(src_el(), "column-gap");
  if (!gap.empty()) {
    style.gap.height = length(gap.front(), src_el());
    style.gap.width = length(gap.back(), src_el());
  }
  if (!rowGap.empty())
    style.gap.height = length(rowGap[0], src_el());
  if (!columnGap.empty())
    style.gap.width = length(columnGap[0], src_el());
  style.align_items = alignment(css().get_flex_align_items());
  style.justify_items = itemKeyword(tokens(src_el(), "justify-items"));
  switch (css().get_flex_justify_content()) {
  case flex_justify_content_center:
    style.justify_content = t::Some(t::JustifyContent::Center);
    break;
  case flex_justify_content_end:
  case flex_justify_content_flex_end:
    style.justify_content = t::Some(t::JustifyContent::End);
    break;
  case flex_justify_content_space_between:
    style.justify_content = t::Some(t::JustifyContent::SpaceBetween);
    break;
  case flex_justify_content_space_around:
    style.justify_content = t::Some(t::JustifyContent::SpaceAround);
    break;
  case flex_justify_content_space_evenly:
    style.justify_content = t::Some(t::JustifyContent::SpaceEvenly);
    break;
  default:
    break;
  }
  t::Vec<t::NodeId> ids;
  std::vector<std::shared_ptr<render_item>> children;
  for (auto &child : m_children) {
    if (child->src_el()->is_positioned() &&
        (child->css().get_position() == element_position_absolute ||
         child->css().get_position() == element_position_fixed))
      continue;
    auto s = t::Style::Default();
    s.size = {dimension(child->css().get_width()),
              dimension(child->css().get_height())};
    s.min_size = {dimension(child->css().get_min_width()),
                  dimension(child->css().get_min_height())};
    s.max_size = {dimension(child->css().get_max_width()),
                  dimension(child->css().get_max_height())};
    s.grid_row = lines(child->src_el(), "grid-row");
    s.grid_column = lines(child->src_el(), "grid-column");
    const auto area = tokens(child->src_el(), "grid-area");
    if (area.size() == 1 && area[0].type == IDENT &&
        areas.named.count(area[0].name)) {
      auto v = areas.named.at(area[0].name);
      auto line = [](int n) { return t::GridPlacement::Line(t::GridLine(n)); };
      s.grid_row = {line(v.top), line(v.bottom)};
      s.grid_column = {line(v.left), line(v.right)};
    } else if (!area.empty()) {
      std::vector<css_token_vector> parts(1);
      for (const auto &v : area) {
        if (v.type == '/')
          parts.emplace_back();
        else
          parts.back().push_back(v);
      }
      if (parts.size() <= 4) {
        parts.resize(4);
        s.grid_row = {placement(parts[0]), placement(parts[2])};
        s.grid_column = {placement(parts[1]), placement(parts[3])};
      }
    }
    s.justify_self = itemKeyword(tokens(child->src_el(), "justify-self"));
    s.align_self = alignment(child->css().get_flex_align_self());
    auto measure = t::MeasureFunc::Raw(
        [&box, child, fmt](const t::Size<t::Option<float>> &known,
                           const t::Size<t::AvailableSpace> &available) {
          const float w = known.width.unwrap_or(
              available.width.unwrap_or(box.render_width));
          const auto intrinsic = child->render(
              0, 0,
              box.new_width(w, containing_block_context::size_mode_content),
              fmt);
          const float autoWidth =
              available.width.type() == t::AvailableSpace::Type::MinContent
                  ? intrinsic.min_width
                  : intrinsic.natural_width;
          return t::Size<float>{known.width.unwrap_or(autoWidth),
                                known.height.unwrap_or(child->height())};
        });
    ids.push_back(tree.new_leaf_with_measure(s, measure).unwrap());
    children.push_back(child);
  }
  auto node = tree.new_with_children(style, ids).unwrap();
  tree.compute_layout(node, {t::AvailableSpace::Definite(box.render_width),
                             t::AvailableSpace::MaxContent()})
      .unwrap();
  auto layout = tree.layout(node).unwrap().get();
  for (size_t i = 0; i < ids.size(); i++) {
    const auto &r = tree.layout(ids[i]).unwrap().get();
    auto &c = children[i];
    c->render(r.location.x, r.location.y,
              box.new_width_height(
                  std::max(0.f, r.size.width - c->content_offset_width() +
                                    c->box_sizing_width()),
                  std::max(0.f, r.size.height - c->content_offset_height() +
                                    c->box_sizing_height()),
                  containing_block_context::size_mode_exact_width |
                      containing_block_context::size_mode_exact_height),
              fmt);
  }
  m_pos.height = layout.size.height;
  m_pos.move_to(x + content_offset_left(), y + content_offset_top());
  return {layout.size.width, layout.size.width};
}
} // namespace litehtml
