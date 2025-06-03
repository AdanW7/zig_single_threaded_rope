const std = @import("std");
const testing = std.testing;

pub const Rope = struct {
    allocator: std.mem.Allocator,
    root: ?*Node,

    const LEAF_MAX_SIZE = 128;
    const MIN_LEAF_SIZE = 64;
    const REBALANCE_THRESHOLD = 1.8;

    pub fn init(allocator: std.mem.Allocator) Rope {
        return Rope{
            .allocator = allocator,
            .root = null,
        };
    }

    pub fn deinit(self: *Rope) void {
        if (self.root) |root| {
            self.destroyNode(root);
        }
        self.root = null;
    }

    pub const Node = struct {
        left_child: ?*Node,
        right_child: ?*Node,
        str: ?[]u8,
        weight: usize,
        height: u8,
        is_leaf: bool,

        pub fn init(allocator: std.mem.Allocator, text: ?[]const u8, is_leaf: bool) error{OutOfMemory}!*Node {
            const node = try allocator.create(Node);
            errdefer allocator.destroy(node);

            node.* = Node{
                .left_child = null,
                .right_child = null,
                .str = null,
                .weight = 0,
                .height = 1,
                .is_leaf = is_leaf,
            };

            if (text) |t| {
                if (is_leaf) {
                    node.str = try allocator.dupe(u8, t);
                    node.weight = t.len;
                }
            }

            return node;
        }

        pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
            if (self.str) |str| {
                allocator.free(str);
            }
            allocator.destroy(self);
        }
    };

    fn destroyNode(self: *Rope, node: *Node) void {
        if (node.left_child) |left| {
            self.destroyNode(left);
        }
        if (node.right_child) |right| {
            self.destroyNode(right);
        }
        node.deinit(self.allocator);
    }


    fn getTotalWeight(self: *Rope, node: ?*Node) usize {
        if (node) |n| {
            if (n.is_leaf) {
                return if (n.str) |s| s.len else 0;
            } else {
                return self.getTotalWeight(n.left_child) + self.getTotalWeight(n.right_child);
            }
        }
        return 0;
    }

    pub fn len(self: *Rope) usize {
        return self.getTotalWeight(self.root);
    }

    /// Build entirely new rope from string
    pub fn build(self: *Rope, text: []const u8) error{OutOfMemory}!void {
        if (self.root) |root| {
            self.destroyNode(root);
        }
        self.root = try self.buildFromString(text);
    }

    fn buildFromString(self: *Rope, text: []const u8) error{OutOfMemory}!*Node {
        if (text.len <= LEAF_MAX_SIZE) {
            return Node.init(self.allocator, text, true);
        }

        // try to split on word boundaries when possible
        const mid = self.findBestSplit(text);
        const left = try self.buildFromString(text[0..mid]);
        errdefer self.destroyNode(left);

        const right = try self.buildFromString(text[mid..]);
        errdefer self.destroyNode(right);

        const internal = try Node.init(self.allocator, null, false);
        errdefer internal.deinit(self.allocator);

        internal.left_child = left;
        internal.right_child = right;
        internal.weight = self.getTotalWeight(left);
        internal.height = 1 + @max(self.getHeight(left), self.getHeight(right));

        return internal;
    }

    /// preferring word boundary for split
    fn findBestSplit(self: *Rope, text: []const u8) usize {
        _ = self;
        const mid = text.len / 2;
        const search_range = @min(MIN_LEAF_SIZE/4, text.len / 4);

        // Look for whitespace near the midpoint
        var best_split = mid;
        var distance_from_mid: usize = 0;

        while (distance_from_mid < search_range) : (distance_from_mid += 1) {

            // check before midpoint
            if (mid >= distance_from_mid) {
                const pos = mid - distance_from_mid;
                if (pos > 0 and std.ascii.isWhitespace(text[pos])) {
                    best_split = pos;
                    break;
                }
            }

            // check after midpoint
            if (mid + distance_from_mid < text.len) {
                const pos = mid + distance_from_mid;
                if (pos > 0 and std.ascii.isWhitespace(text[pos])) {
                    best_split = pos;
                    break;
                }
            }
        }

        return best_split;
    }

    fn getHeight(self: *Rope, node: ?*Node) u8 {
        _ = self;
        return if (node) |n| n.height else 0;
    }

    /// Get char at global/root index
    pub fn index(self: *Rope, idx: usize) ?u8 {
        if (idx >= self.len()) return null;
        if (self.root) |root| {
            return self.indexNode(root, idx);
        }
        return null;
    }

    /// Get char at local/relative node index
    fn indexNode(self: *Rope, node: *Node, idx: usize) ?u8 {
        if (node.is_leaf) {
            if (node.str) |str| {
                if (idx < str.len) {
                    return str[idx];
                }
            }
            return null;
        }

        if (idx < node.weight) {
            if (node.left_child) |left| {
                return self.indexNode(left, idx);
            }
        } else {
            if (node.right_child) |right| {
                return self.indexNode(right, idx - node.weight);
            }
        }
        return null;
    }

    ///remove >=idx from global rope, return an optional Node ptr
    pub fn split(self: *Rope, idx: usize) error{OutOfMemory}!?*Node {
        if (idx == 0) {
            const result = self.root;
            self.root = null;
            return result;
        }
        if (idx >= self.len()) {
            return null;
        }
        if (self.root) |root| { // standard split method
            const result = try self.splitNode(root, idx);
            self.root = result.left;
            return result.right;
        }
        return null;
    }

    const SplitResult = struct {
        left: ?*Node,
        right: ?*Node,
    };

    fn splitNode(self: *Rope, node: *Node, idx: usize) error{OutOfMemory}!SplitResult {
        if (node.is_leaf) {
            if (node.str) |str| {
                if (idx >= str.len) {
                    return SplitResult{ .left = node, .right = null };
                }
                if (idx == 0) {
                    return SplitResult{ .left = null, .right = node };
                }

                const left_node = try Node.init(self.allocator, str[0..idx], true);
                errdefer left_node.deinit(self.allocator);

                const right_node = try Node.init(self.allocator, str[idx..], true);
                errdefer right_node.deinit(self.allocator);

                node.deinit(self.allocator);

                return SplitResult{ .left = left_node, .right = right_node };
            }
            return SplitResult{ .left = null, .right = null };
        }

        if (idx < node.weight) { // split left child
            if (node.left_child) |left| {
                const left_split = try self.splitNode(left, idx);

                var new_right: ?*Node = null;
                if (left_split.right) |l_split_right| {
                    new_right = try Node.init(self.allocator, null, false);
                    errdefer if (new_right) |nr| nr.deinit(self.allocator);

                    new_right.?.left_child = l_split_right;
                    new_right.?.right_child = node.right_child;
                    new_right.?.weight = self.getTotalWeight(l_split_right);
                    new_right.?.height = 1 + @max(self.getHeight(l_split_right), self.getHeight(node.right_child));
                }

                // update og node
                node.right_child = null; // ownership transferred to new_right
                node.left_child = left_split.left;
                node.weight = self.getTotalWeight(node.left_child);
                node.height = 1 + @max(self.getHeight(node.left_child), 0);

                return SplitResult{ .left = node, .right = new_right };
            }
        } else { //  idx >= node.weight -> split right child
            if (node.right_child) |right| {
                const right_split = try self.splitNode(right, idx - node.weight);

                // update og node
                node.right_child = right_split.left;
                node.height = 1 + @max(self.getHeight(node.left_child), self.getHeight(node.right_child));

                return SplitResult{ .left = node, .right = right_split.right };
            }
        }

        return SplitResult{ .left = node, .right = null };
    }

    pub fn concat(self: *Rope, other: *Node) error{OutOfMemory}!void {
        if (self.root) |root| {
            const new_root = try Node.init(self.allocator, null, false);
            errdefer new_root.deinit(self.allocator);

            new_root.left_child = root;
            new_root.right_child = other;
            new_root.weight = self.getTotalWeight(root);
            new_root.height = 1 + @max(self.getHeight(root), self.getHeight(other));
            self.root = new_root;

            if (self.shouldRebalance()) {
                try self.rebalance();
            }
        } else { // if concat to null rope root
            self.root = other;
        }
    }

    fn shouldRebalance(self: *Rope) bool {
        if (self.root) |root| {
            const rope_len = self.len();
            if (rope_len < 2) return false;

            const ideal_height = std.math.log2_int(usize, rope_len) + 1;
            const actual_height = root.height;

            return @as(f64, @floatFromInt(actual_height)) >
                @as(f64, @floatFromInt(ideal_height)) * REBALANCE_THRESHOLD;
        }
        return false;
    }

    pub fn insert(self: *Rope, idx: usize, text: []const u8) !void {
        if (text.len == 0) return;

        //  insertion at the end
        if (idx >= self.len()) {
            return self.append(text);
        }

        //  insertion at the beginning
        if (idx == 0) {
            const new_node = try self.buildFromString(text);
            const old_root = self.root;
            self.root = new_node;
            if (old_root) |root| {
                try self.concat(root);
            }
            return;
        }

        //  merge with adjacent leaf if possible
        if (try self.tryMergeInsert(idx, text)) {
            return;
        }

        // ball back to split-insert-concat
        const right_part = try self.split(idx);
        const new_node = try self.buildFromString(text);
        try self.concat(new_node);
        if (right_part) |right| {
            try self.concat(right);
        }
    }

    const MergeInfo = struct {
        leaf: *Node,
        idx: usize,
    };

    /// try to merge small inserts with adjacent leaves
    fn tryMergeInsert(self: *Rope, idx: usize, text: []const u8) error{OutOfMemory}!bool {
        if (text.len > LEAF_MAX_SIZE / 4) return false; // only merge small inserts

        // find leaf containing this idx
        if (self.root) |root| {
            if (self.findLeafForMerge(root, idx, text)) |merge_info| {
                const leaf = merge_info.leaf;
                const leaf_idx = merge_info.idx;

                if (leaf.str) |old_str| {
                    if (old_str.len + text.len <= LEAF_MAX_SIZE) {
                        const new_str = try self.allocator.alloc(u8, old_str.len + text.len);
                        errdefer self.allocator.free(new_str);

                        @memcpy(new_str[0..leaf_idx], old_str[0..leaf_idx]);
                        @memcpy(new_str[leaf_idx .. leaf_idx + text.len], text);
                        @memcpy(new_str[leaf_idx + text.len ..], old_str[leaf_idx..]);

                        self.allocator.free(old_str);
                        leaf.str = new_str;
                        leaf.weight = new_str.len;

                        // update weights in parent nodes
                        self.updateWeights(root);
                        return true;
                    }
                }
            }
        }
        return false;
    }

    fn findLeafForMerge(self: *Rope, node: *Node, idx: usize, text: []const u8) ?MergeInfo {
        if (node.is_leaf) {
            return MergeInfo{ .leaf = node, .idx = idx };
        }
        if (idx < node.weight) {
            if (node.left_child) |left| {
                return self.findLeafForMerge(left, idx, text);
            }
        } else {
            if (node.right_child) |right| {
                return self.findLeafForMerge(right, idx - node.weight, text);
            }
        }
        return null;
    }

    fn updateWeights(self: *Rope, node: *Node) void {
        if (!node.is_leaf) {
            node.weight = self.getTotalWeight(node.left_child);
            node.height = 1 + @max(self.getHeight(node.left_child), self.getHeight(node.right_child));

            if (node.left_child) |left| {
                self.updateWeights(left);
            }
            if (node.right_child) |right| {
                self.updateWeights(right);
            }
        }
    }

    pub fn append(self: *Rope, text: []const u8) error{OutOfMemory}!void {
        if (text.len == 0) return;

        // try to merge with the rightmost leaf if it's small enough
        if (self.root) |root| {
            if (self.tryAppendToLastLeaf(root, text)) {
                self.updateWeights(root);
                return;
            }
        }

        // fall back -> create new node and concat
        const new_node = try self.buildFromString(text);
        try self.concat(new_node);
    }

    fn tryAppendToLastLeaf(self: *Rope, node: *Node, text: []const u8) bool {
        if (node.is_leaf) {
            if (node.str) |old_str| {
                // only merge if the result fits
                if (old_str.len + text.len <= LEAF_MAX_SIZE) {
                    const new_str = self.allocator.realloc(old_str, old_str.len + text.len) catch return false;
                    @memcpy(new_str[old_str.len..], text);
                    node.str = new_str;
                    node.weight = new_str.len;
                    return true;
                }
            }
            return false;
        }

        // try rightmost child first
        if (node.right_child) |right| {
            if (self.tryAppendToLastLeaf(right, text)) {
                return true;
            }
        }

        // if no right child, then try left child
        if (node.left_child) |left| {
            return self.tryAppendToLastLeaf(left, text);
        }

        return false;
    }

    /// specify a range of indexs to delete from the rope
    pub fn delete(self: *Rope, start_idx: usize, end_idx: usize) error{OutOfMemory}!void {
        if (start_idx >= end_idx or start_idx >= self.len()) return;

        const actual_end = @min(end_idx, self.len());

        if (start_idx == 0 and actual_end >= self.len()) { //recursively free all Nodes in rope
            if (self.root) |root| {
                self.destroyNode(root);
                self.root = null;
            }
            return;
        }

        const right_node = try self.split(actual_end);
        const deleted_node = try self.split(start_idx);

        // recursively free deleted memory
        if (deleted_node) |dn| {
            self.destroyNode(dn);
        }

        if (right_node) |right| {
            try self.concat(right);
        }

        try self.mergeSmallLeaves();
    }

    /// merge small adjacent leaves -> prevent over-fragmentation
    fn mergeSmallLeaves(self: *Rope) error{OutOfMemory}!void {
        if (self.root) |root| {
            _ = try self.mergeSmallLeavesRecursive(root); 
        }
    }

    fn mergeSmallLeavesRecursive(self: *Rope, node: *Node) error{OutOfMemory}!bool {
        if (node.is_leaf) return false;

        var changed = false;

        // recursively merge child nodes from left to right
        if (node.left_child) |left| {
            if (try self.mergeSmallLeavesRecursive(left)) {
                changed = true;
            }
        }
        if (node.right_child) |right| {
            if (try self.mergeSmallLeavesRecursive(right)) {
                changed = true;
            }
        }

        // try to merge if both children are small leaves
        if (node.left_child) |left| {
            if (node.right_child) |right| {
                if (left.is_leaf and right.is_leaf) {
                    if (left.str) |left_str| {
                        if (right.str) |right_str| {
                            // check that summation of str lens < max leaf and that both are small enough to merge
                            if (left_str.len + right_str.len <= LEAF_MAX_SIZE and
                                left_str.len < MIN_LEAF_SIZE and right_str.len < MIN_LEAF_SIZE)
                            {

                                // Merge the two leaves
                                const merged_str = try self.allocator.alloc(u8, left_str.len + right_str.len);
                                errdefer self.allocator.free(merged_str);

                                @memcpy(merged_str[0..left_str.len], left_str);
                                @memcpy(merged_str[left_str.len..], right_str);

                                // internal node becomes a leaf, deallocate unowned Nodes
                                self.destroyNode(left);
                                self.destroyNode(right);

                                node.left_child = null;
                                node.right_child = null;
                                node.str = merged_str;
                                node.weight = merged_str.len;
                                node.height = 1;
                                node.is_leaf = true;

                                changed = true;
                            }
                        }
                    }
                }
            }
        }

        // update weights and heights if node is changed
        if (changed and !node.is_leaf) {
            node.weight = self.getTotalWeight(node.left_child);
            node.height = 1 + @max(self.getHeight(node.left_child), self.getHeight(node.right_child));
        }

        return changed;
    }

    /// returns a complete string of all leaves in the rope
    pub fn collectLeaves(self: *Rope, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        const total_len = self.len();
        var result = try std.ArrayList(u8).initCapacity(allocator, total_len);

        if (self.root) |root| {
            self.collectLeavesRecursive(root, &result);
        }

        return try result.toOwnedSlice(); // no need to call deinit on result, function caller takes ownership of result
    }

    fn collectLeavesRecursive(self: *Rope, node: *Node, result: *std.ArrayList(u8)) void {
        if (node.is_leaf) {
            if (node.str) |str| {
                result.appendSliceAssumeCapacity(str);
            }
        } else {
            if (node.left_child) |left| {
                self.collectLeavesRecursive(left, result);
            }
            if (node.right_child) |right| {
                self.collectLeavesRecursive(right, result);
            }
        }
    }

    /// returns index of first match of pattern in rope
    pub fn find(self: *Rope, pattern: []const u8) ?usize {
        if (pattern.len == 0) return 0;
        if (self.root == null or pattern.len > self.len()) return null;

        // for small patterns
        if (pattern.len <= 16) {
            return self.findSimple(pattern);
        }

        // for larger patterns, collect text and use std.mem.indexOf
        const text = self.collectLeaves(self.allocator) catch return null;
        defer self.allocator.free(text);
        return std.mem.indexOf(u8, text, pattern);
    }

    fn findSimple(self: *Rope, pattern: []const u8) ?usize {
        const rope_len = self.len();
        if (pattern.len > rope_len) return null;

        outer: for (0..rope_len - pattern.len + 1) |i| {
            for (pattern, 0..) |expected_char, j| {
                if (self.index(i + j) != expected_char) {
                    continue :outer;
                }
            }
            return i;
        }
        return null;
    }

    ///returns a slice containing all idx in rope where pattern is found
    pub fn findAll(self: *Rope, pattern: []const u8, allocator: std.mem.Allocator) error{OutOfMemory}![]usize {
        if (pattern.len == 0 or self.root == null or pattern.len > self.len()) {
            return allocator.alloc(usize, 0);
        }

        var matches = std.ArrayList(usize).init(allocator);

        var search_start: usize = 0;
        while (search_start < self.len()) {
            if (self.findFrom(pattern, search_start)) |idx| {
                try matches.append(idx);
                search_start = idx + 1; // move past this match to find others
            } else {
                break;
            }
        }
        return matches.toOwnedSlice();
    }


    /// replaces all instances of pattern in rope with replacement
    pub fn replace(self: *Rope, pattern: []const u8, replacement: []const u8) error{OutOfMemory}!usize {
        var replacements: usize = 0;
        var search_start: usize = 0;

        while (search_start < self.len()) {
            if (self.findFrom(pattern, search_start)) |idx| {
                try self.delete(idx, idx + pattern.len);
                try self.insert(idx, replacement);
                search_start = idx + replacement.len;
                replacements += 1;
            } else {
                break;
            }
        }

        return replacements;
    }
    // needs to be implemented
    pub fn replaceRange(self: *Rope, start_idx: usize, end_idx:usize,replacement: []const u8 )bool{
        var succeed = false;
        _ = self;
        _ = start_idx;
        _ = end_idx;
        _ = replacement;

        if(true) {
            succeed = true;
        }

        return succeed;
    }

    ///replaces a single instances of pattern with replacement if it does exist in rope at provided index
    pub fn replaceIndex(self: *Rope, pattern: []const u8, replacement: []const u8, idx: usize) error{IndexExceedsLen,PatternNotAtIndex,OutOfMemory}!void {
        if (idx >= self.len() or idx + pattern.len > self.len()) {
            return error.IndexExceedsLen;
        }

        for (pattern, 0..) |expected_char, j| {
            if (self.index(idx + j) != expected_char) {
                return error.PatternNotAtIndex;
            }
        }
        try self.delete(idx, idx + pattern.len);
        try self.insert(idx, replacement);
    }

    fn findFrom(self: *Rope, pattern: []const u8, start_idx: usize) ?usize {
        if (start_idx >= self.len()) {
            return null;
        }
        const rope_len = self.len();
        if (start_idx + pattern.len > rope_len){
            return null;
        }
        const search_len = rope_len - start_idx;

        var buffer = std.ArrayList(u8).initCapacity(self.allocator, search_len) catch {
            return null;
        };
        defer buffer.deinit();

        for (start_idx..rope_len) |idx| {
            if (self.index(idx)) |i| {
                buffer.appendAssumeCapacity(i);
            }
        }
        if (std.mem.indexOf(u8, buffer.items, pattern)) |relative_idx| {
            return start_idx + relative_idx;
        }
        return null;
    }

    pub fn getLine(self: *Rope, line_num: usize, allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
        var current_line: usize = 0;
        var line_start: usize = 0;

        const rope_len = self.len();
        for (0..rope_len) |i| {
            if (self.index(i) == '\n') {
                if (current_line == line_num) {
                    return try self.substring(line_start, i, allocator);
                }
                current_line += 1;
                line_start = i + 1;
            }
        }

        // Handle last line without newline
        if (current_line == line_num and line_start < rope_len) {
            return try self.substring(line_start, rope_len, allocator);
        }

        return null;
    }

    pub fn countLines(self: *Rope) usize {
        if (self.len() == 0) return 0;

        var count: usize = 1;
        for (0..self.len()) |i| {
            if (self.index(i) == '\n') {
                count += 1;
            }
        }
        return count;
    }

    // Optimized substring extraction
    pub fn substring(self: *Rope, start_idx: usize, end_idx: usize, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        const actual_start = @min(start_idx, self.len());
        const actual_end = @min(end_idx, self.len());

        if (actual_start >= actual_end) {
            return try allocator.dupe(u8, "");
        }

        const result_len = actual_end - actual_start;
        var result = try std.ArrayList(u8).initCapacity(allocator, result_len);
        defer result.deinit();

        if (self.root) |root| {
            try self.substringRecursive(root, actual_start, actual_end, 0, &result);
        }

        return try result.toOwnedSlice();
    }

    fn substringRecursive(self: *Rope, node: *Node, start: usize, end: usize, offset: usize, result: *std.ArrayList(u8)) error{OutOfMemory}!void {
        if (node.is_leaf) {
            if (node.str) |str| {
                const node_end = offset + str.len;
                if (start < node_end and end > offset) {
                    const slice_start = if (start > offset) start - offset else 0;
                    const slice_end = if (end < node_end) end - offset else str.len;
                    if (slice_start < slice_end) {
                        result.appendSliceAssumeCapacity(str[slice_start..slice_end]);
                    }
                }
            }
        } else {
            const left_end = offset + node.weight;
            if (start < left_end) {
                if (node.left_child) |left| {
                    try self.substringRecursive(left, start, end, offset, result);
                }
            }
            if (end > left_end) {
                if (node.right_child) |right| {
                    try self.substringRecursive(right, start, end, left_end, result);
                }
            }
        }
    }

    // only use for debugging
    pub fn report(self: *Rope) void {
        std.debug.print("Rope structure:\n", .{});
        if (self.root) |root| {
            self.reportNode(root, 0);
        } else {
            std.debug.print("  (empty)\n", .{});
        }
        std.debug.print("Total length: {}\n", .{self.len()});
        std.debug.print("Tree height: {}\n", .{self.getHeight(self.root)});
        std.debug.print("Balance factor: {d:.2}\n", .{self.getBalanceFactor()});
    }

    fn getBalanceFactor(self: *Rope) f64 {
        const rope_len = self.len();
        if (rope_len < 2) return 1.0;

        const ideal_height = std.math.log2_int(usize, rope_len) + 1;
        const actual_height = self.getHeight(self.root);

        return @as(f64, @floatFromInt(actual_height)) / @as(f64, @floatFromInt(ideal_height));
    }

    fn reportNode(self: *Rope, node: *Node, depth: usize) void {
        for (0..depth) |_| {
            std.debug.print("  ", .{});
        }

        if (node.is_leaf) {
            const str = if (node.str) |s| s else "";
            const preview = if (str.len > 20) str[0..17] ++ "..." else str;
            std.debug.print("Leaf: \"{s}\" (len: {}, weight: {}, height: {})\n", .{ preview, str.len, node.weight, node.height });
        } else {
            std.debug.print("Internal (weight: {}, height: {})\n", .{ node.weight, node.height });
            if (node.left_child) |left| {
                self.reportNode(left, depth + 1);
            }
            if (node.right_child) |right| {
                self.reportNode(right, depth + 1);
            }
        }
    }

    pub fn rebalance(self: *Rope) error{OutOfMemory}!void {
        const text = try self.collectLeaves(self.allocator);
        defer self.allocator.free(text);
        try self.build(text);
    }

    pub const Iterator = struct {
        rope: *Rope,
        current_pos: usize,

        pub fn init(rope: *Rope) Iterator {
            return Iterator{
                .rope = rope,
                .current_pos = 0,
            };
        }

        pub fn next(self: *Iterator) ?u8 {
            if (self.current_pos >= self.rope.len()) {
                return null;
            }

            const char = self.rope.index(self.current_pos);
            self.current_pos += 1;
            return char;
        }

        pub fn peek(self: *Iterator) ?u8 {
            if (self.current_pos >= self.rope.len()) {
                return null;
            }
            return self.rope.index(self.current_pos);
        }

        pub fn reset(self: *Iterator) void {
            self.current_pos = 0;
        }

        pub fn seek(self: *Iterator, pos: usize) void {
            self.current_pos = @min(pos, self.rope.len());
        }
    };

    pub fn iterator(self: *Rope) Iterator {
        return Iterator.init(self);
    }
};

// Enhanced test suite
test "rope basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rope = Rope.init(allocator);
    defer rope.deinit();

    // Test build
    try rope.build("Hello, World!");
    try testing.expect(rope.len() == 13);

    // Test index
    try testing.expect(rope.index(0).? == 'H');
    try testing.expect(rope.index(7).? == 'W');
    try testing.expect(rope.index(12).? == '!');

    // Test bounds checking
    try testing.expect(rope.index(13) == null);
    try testing.expect(rope.index(100) == null);

    // Test append
    try rope.append(" How are you?");
    try testing.expect(rope.len() == 26);

    // Test insert
    try rope.insert(13, " Beautiful");
    try testing.expect(rope.len() == 36);

    // Test collect
    const result = try rope.collectLeaves(allocator);
    defer allocator.free(result);
    try testing.expectEqualStrings(result, "Hello, World! Beautiful How are you?");
}

test "rope advanced operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rope = Rope.init(allocator);
    defer rope.deinit();

    // Test line operations
    try rope.build("Hello\nWorld\nHow are you?");
    try testing.expect(rope.countLines() == 3);

    const line1 = try rope.getLine(1, allocator);
    if (line1) |l1| {
        defer allocator.free(l1);
        try testing.expectEqualStrings(l1, "World");
    }

    // Test find and replace
    try testing.expect(rope.find("World") == 6);
    const replacements = try rope.replace("World", "Universe");
    try testing.expect(replacements == 1);

    const result = try rope.collectLeaves(allocator);
    defer allocator.free(result);
    try testing.expectEqualStrings(result, "Hello\nUniverse\nHow are you?");
}

test "rope split and concat" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rope = Rope.init(allocator);
    defer rope.deinit();

    try rope.build("Hello World");

    // Split at index 6 (after "Hello ")
    const right_part = try rope.split(6);

    // Left part should be "Hello "
    const left_text = try rope.collectLeaves(allocator);
    defer allocator.free(left_text);
    try testing.expectEqualStrings(left_text, "Hello ");

    // Concatenate back
    if (right_part) |right| {
        try rope.concat(right);
    }

    const full_text = try rope.collectLeaves(allocator);
    defer allocator.free(full_text);
    try testing.expectEqualStrings(full_text, "Hello World");
}

test "rope iterator" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rope = Rope.init(allocator);
    defer rope.deinit();

    try rope.build("Hello");

    var iter = rope.iterator();
    try testing.expect(iter.next().? == 'H');
    try testing.expect(iter.next().? == 'e');
    try testing.expect(iter.peek().? == 'l');
    try testing.expect(iter.next().? == 'l');
    try testing.expect(iter.next().? == 'l');
    try testing.expect(iter.next().? == 'o');
    try testing.expect(iter.next() == null);
}

test "rope large text performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rope = Rope.init(allocator);
    defer rope.deinit();

    // Build large text
    const large_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ** 100;
    try rope.build(large_text);

    // Test operations on large text
    try rope.insert(1000, "INSERTED");
    try testing.expect(rope.len() == large_text.len + 8);

    try rope.delete(1000, 1008);
    try testing.expect(rope.len() == large_text.len);

    // Test substring
    const substr = try rope.substring(0, 100, allocator);
    defer allocator.free(substr);
    try testing.expect(substr.len == 100);
}
