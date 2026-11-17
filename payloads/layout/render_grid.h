#pragma once
#include "render_flex.h"
namespace litehtml {
class render_item_grid final : public render_item_flex {
  rendered_width _render_content(pixel_t, pixel_t, bool,
                                 const containing_block_context &,
                                 formatting_context *) override;

public:
  explicit render_item_grid(std::shared_ptr<element> el)
      : render_item_flex(std::move(el)) {}
  std::shared_ptr<render_item> clone() override {
    return std::make_shared<render_item_grid>(src_el());
  }
};
} // namespace litehtml
