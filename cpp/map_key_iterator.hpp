#pragma once

// This class/idea/idiom taken from a reply on stackoverflow (but I
// cannot find the original author).  XXX Add missing attribution for
// this code.

#include <map>
#include <iterator>

namespace frobware {

template<typename map_type>
class key_iterator : public map_type::iterator
{
 public:
  typedef typename map_type::iterator map_iterator;
  typedef typename map_iterator::value_type::first_type key_type;

  key_iterator(map_iterator& other) :map_type::iterator(other) {};

  key_type& operator*() {
    return map_type::iterator::operator*().first;
  }
};

template<typename map_type>
key_iterator<map_type> key_begin(map_type& m)
{
  return key_iterator<map_type>(m.begin());
}

template<typename map_type>
key_iterator<map_type> key_end(map_type& m)
{
  return key_iterator<map_type>(m.end());
}

template<typename map_type>
class const_key_iterator : public map_type::const_iterator
{
 public:
  typedef typename map_type::const_iterator map_iterator;
  typedef typename map_iterator::value_type::first_type key_type;

  const_key_iterator(const map_iterator& other) :map_type::const_iterator(other) {};

  const key_type& operator*() const {
    return map_type::const_iterator::operator*().first;
  }
};

template<typename map_type>
const_key_iterator<map_type> key_begin(const map_type& m)
{
  return const_key_iterator<map_type>(m.begin());
}

template<typename map_type>
const_key_iterator<map_type> key_end(const map_type& m)
{
  return const_key_iterator<map_type>(m.end());
}
}
