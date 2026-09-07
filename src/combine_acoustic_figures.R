library(cowplot)
library(ggplot2)
library(png)

figures_dir <- "figures_colorblind"

image_panel <- function(path) {
  raster <- readPNG(path)
  ggdraw() + draw_grob(grid::rasterGrob(raster, interpolate = TRUE))
}

f0_panel <- image_panel(file.path(figures_dir, "raw_f0_contour.png"))
range_panel <- image_panel(file.path(figures_dir, "pitch_range_boxplot.png"))
rate_panel <- image_panel(file.path(figures_dir, "speaking_rate_boxplot.png"))

bottom_row <- plot_grid(
  range_panel,
  rate_panel,
  labels = c("B", "C"),
  label_size = 16,
  label_fontface = "bold",
  nrow = 1
)

combined <- plot_grid(
  f0_panel,
  NULL,
  bottom_row,
  labels = c("A", "", ""),
  label_size = 16,
  label_fontface = "bold",
  ncol = 1,
  rel_heights = c(1, 0.08, 1.05)
)

ggsave(
  file.path(figures_dir, "acoustic_measurements_combined.png"),
  combined,
  width = 12,
  height = 8,
  dpi = 300,
  bg = "white"
)
