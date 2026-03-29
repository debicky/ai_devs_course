# frozen_string_literal: true

require 'tempfile'

module Services
  module Electricity
    class PixelSolver
      # Both images, when thresholded and trimmed, yield the same 517x359 content area.
      # Grid borders within that area (found via column/row intensity scanning):
      #   Vertical:   x = 108, 204, 300, 393
      #   Horizontal: y =  70, 166, 262, 354
      # Cell interiors (skip border pixels):
      CELL_X_START = 112
      CELL_Y_START = 74
      CELL_W       = 88
      CELL_H       = 88
      CELL_STEP_X  = 96  # distance between cell starts (border-to-border)
      CELL_STEP_Y  = 96

      def solve(current_png_data, solved_png_path)
        Dir.mktmpdir('elec') do |dir|
          current_path = File.join(dir, 'current.png')
          File.binwrite(current_path, current_png_data)

          # Threshold + trim both to same content area
          current_prep = prep_image(current_path, dir, 'cur')
          solved_prep  = prep_image(solved_png_path, dir, 'sol')

          rotations = {}
          (1..3).each do |row|
            (1..3).each do |col|
              cell = "#{row}x#{col}"
              n = best_rotation_for_cell(current_prep, solved_prep, row, col, dir)
              rotations[cell] = n if n.positive?
              puts "  #{cell}: #{n} rotation(s)"
            end
          end

          rotations
        end
      end

      private

      def prep_image(path, dir, prefix)
        out = File.join(dir, "#{prefix}_prep.png")
        system(
          'magick', path,
          '-threshold', '40%',
          '-trim', '+repage',
          out
        )
        out
      end

      def crop_cell(image_path, row, col, dir, prefix)
        x = CELL_X_START + (col - 1) * CELL_STEP_X
        y = CELL_Y_START + (row - 1) * CELL_STEP_Y
        out = File.join(dir, "#{prefix}_#{row}x#{col}.png")
        system(
          'magick', image_path,
          '-crop', "#{CELL_W}x#{CELL_H}+#{x}+#{y}", '+repage',
          out
        )
        out
      end

      def best_rotation_for_cell(current_prep, solved_prep, row, col, dir)
        solved_cell  = crop_cell(solved_prep, row, col, dir, 'sol')
        current_cell = crop_cell(current_prep, row, col, dir, 'cur')

        best_n     = 0
        best_score = compare(current_cell, solved_cell)

        rotated = current_cell
        (1..3).each do |n|
          rotated_path = File.join(dir, "cur_#{row}x#{col}_r#{n}.png")
          system('magick', rotated, '-rotate', '90', rotated_path)
          rotated = rotated_path

          score = compare(rotated, solved_cell)
          if score < best_score
            best_score = score
            best_n = n
          end
        end

        best_n
      end

      def compare(path_a, path_b)
        result = `magick compare -metric MAE "#{path_a}" "#{path_b}" /dev/null 2>&1`
        match = result.match(/\(([\d.]+)\)/)
        match ? match[1].to_f : 999.0
      end
    end
  end
end
