import sys

'''
example:
$ python anagram.py "listen, silent, enlist, google, dog, god"
(listen, silent, enlist) ( dog, god) %


what is the order of time complexity of this
main function where each word has max length N?

Time complexity: O(N log N)
word.lower(): O(N) — iterates over all characters
.strip(): O(N) — scans from both ends
sorted(...): O(N log N) — Timsort on a string of length N
Overall it’s O(N) + O(N log N) = O(N log N), since the sort dominates.

what is the order of space complexity of this main
function where each word has max length N?

Space complexity: O(N)
sorted(...): O(N) — creates a new string of length N
Overall it’s O(N), since the new string dominates.
'''


def main(argv):
    if len(argv) != 2:
        print("Usage: python anagram.py <word>")
        sys.exit(1)
    input = argv[1]
    words = input.split(",")
    anagrams = {}
    for word in words:
        key = ''.join(sorted(word.lower().strip()))
        if key not in anagrams:
            anagrams[key] = []
        anagrams[key].append(word)

    for key in anagrams:
        anagram_words = anagrams[key]
        if len(anagram_words) > 1:
            print("(" + ','.join(anagram_words) + ")", end=" ")
    print()


if __name__ == "__main__":
    main(sys.argv)
