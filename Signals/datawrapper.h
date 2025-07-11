#pragma once

#ifdef SIGNALS_EXPORTS
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif

// A wrapper for all signals data. This allows data to be numpy or mxArrays, etc.
template <typename T>
class SIGNALS_API DataContainer {
public:
    DataContainer(size_t size) : size_(size), data_(new T[size]) {}

    ~DataContainer() {
        delete[] data_;
    }

    T& operator[](size_t index) {
        return data_[index];
    }

    const T& operator[](size_t index) const {
        return data_[index];
    }

    size_t size() const {
        return size_;
    }

    T* getData() { return data_; };

    // is the data a single value or an array or some sort
    const bool isScalar = true;  // todo unused

private:
    size_t size_;
    T* data_;
};
