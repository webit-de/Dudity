class GitDiffService
  class << self
    PATTERN_MATCH = /^diff --git\s/
    # restrict scope: for Rails app exclude autogenerated code and omit any files except .rb
    # EXCLUDE_ROOT_FOLDERS = ['db/', 'spec/', 'config/']
    ALLOWED_EXTENSION = '.rb'

    def call(diff_lines, exclude_folders = [])
      @diff_lines = diff_lines
      # TO-DO: support @only_folders
      @exclude_folders = exclude_folders

      patch_pos_start = lines_with_file_paths.map { |line| patch_start_pos(line) }
      # array with start and end positions for each patch
      @patches_pos = patch_pos_start.zip(patch_end_pos(patch_pos_start))
      slice_diff
      @patches = @patches.select { |patch| allowed_patch?(patch) }
      @diff_data = @patches.map { |patch| fname_diff(patch) }
      @diff_data += @patches.map { |patch| class_diff(patch) }
      @diff_data.compact
    end

    private

    # split diff lines into separate patches for each file
    def slice_diff
      @patches = @patches_pos.map { |pos| @diff_lines[pos.first..pos.last] }
    end

    def allowed_patch?(patch)
      fname_string = patch.first
      extension_allowed = extract_file_paths(fname_string).last.end_with?(ALLOWED_EXTENSION)
      folder_allowed = !extract_file_paths(fname_string).last.start_with?(*@exclude_folders)

      extension_allowed && folder_allowed
    end

    def new_file?(patch)
      patch.select { |line| line.start_with?('new file mode ') }.any?
    end

    def deleted_file?(patch)
      patch.select { |line| line.start_with?('deleted file mode ') }.any?
    end

    def renamed_file?(patch)
      patch.select { |line| line.start_with?('rename from ') }.any?
    end

    def class_renamed?(patch)
      patch.select { |line| line.start_with?('-class') }.any? &&
          patch.select { |line| line.start_with?('+class') }.any?
    end

    def old_class_name(patch)
      res = patch.select { |line| line.start_with?('-class') }
      return if res.empty?
      line = res.first
      line.split(' ').last.strip
    end

    def new_class_name(patch)
      res = patch.select { |line| line.start_with?('+class') }
      return if res.empty?
      line = res.first
      line.split(' ').last.strip
    end

    def fname_diff(patch)
      # first line in patch contains info about file path
      file_path_line = patch.first
      return { old_name: extract_file_paths(file_path_line).first,
               new_name: extract_file_paths(file_path_line).last, status: :renamed } if renamed_file?(patch)
      return { old_name: nil, new_name: extract_file_paths(file_path_line).last,
               status: :new } if new_file?(patch)
      return { old_name: extract_file_paths(file_path_line).first,
               new_name: nil,  status: :deleted } if deleted_file?(patch)
      # changed file without renaming
      return { old_name: extract_file_paths(file_path_line).first,
               new_name: extract_file_paths(file_path_line).last,  status: :changed }
    end

    def class_diff(patch)
      return { old_name: old_class_name(patch),
                         new_name: new_class_name(patch), status: :renamed_class } if class_renamed?(patch)
    end

    # end line index for current patch
    def patch_end_pos(patch_pos_start)
      end_line_pos = patch_pos_start.size - 1
      pos_end = patch_pos_start.map.with_index do |pos, i|
        i == patch_pos_start.size - 1 ? @diff_lines.size - 1 : patch_pos_start[i + 1] - 1
      end

      pos_end
    end

    def lines_with_file_paths
      @diff_lines.select { |line| line.scan(PATTERN_MATCH).any? }
    end

    def patch_start_pos(line)
      @diff_lines.index(line)
    end

    def extract_file_paths(line)
      # diff --git a/project_v1/README.md b/project_v2/README2.md
      line = line.delete_prefix('diff --git ')
      path1, path2 = line.split(' ')
      [path1, path2].map! { |path| file_path(path) }
    end

    def file_path(str)
      # a/project_v1/README.md -> project_v1/README.md
      prefix, *path_parts = str.split('/')
      path_parts.join('/')
    end
  end
end